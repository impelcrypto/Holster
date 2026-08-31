import Foundation
import KeyboardShortcuts
import Yams

/// http:// to anything but loopback sends API keys and captured text in
/// cleartext; the UI warns (but does not block, LAN setups are legitimate).
public func isInsecureRemoteURL(_ base: String) -> Bool {
    guard let url = URL(string: base.trimmingCharacters(in: .whitespaces)),
          url.scheme?.lowercased() == "http" else { return false }
    let host = url.host?.lowercased() ?? ""
    return !(host == "localhost" || host.hasSuffix(".localhost")
        || host.hasPrefix("127.") || host == "::1" || host == "[::1]")
}

public struct ProviderConfig: Codable, Equatable {
    public var baseURL: String
    public var apiKey: String?

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case apiKey = "api_key"
    }

    public init(baseURL: String, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

public struct TTSConfig: Codable, Equatable {
    /// "edge" for free Microsoft Edge TTS; otherwise base_url (OpenAI) or built-in.
    public var provider: String?
    public var baseURL: String?
    public var apiKey: String?
    public var model: String?
    public var voice: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case baseURL = "base_url"
        case apiKey = "api_key"
        case model
        case voice
    }

    public init(provider: String? = nil, baseURL: String? = nil, apiKey: String? = nil, model: String? = nil, voice: String? = nil) {
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
    }
}

public struct CommandConfig: Codable, Equatable, Identifiable {
    public var name: String
    public var hotkey: String?
    /// Prompt filename under prompts/, e.g. "grammar.md".
    public var prompt: String
    public var provider: String?
    public var model: String
    /// Reasoning effort ("low" / "medium" / "high"); nil sends nothing.
    public var reasoning: String?
    /// Selecting text in the result window copies it automatically.
    public var copyOnSelect: Bool?
    /// Used when the primary provider fails before any content arrives.
    public var fallbackProvider: String?
    public var fallbackModel: String?

    public var id: String { name }
    public var wantsCopyOnSelect: Bool { copyOnSelect ?? false }

    enum CodingKeys: String, CodingKey {
        case name, hotkey, prompt, provider, model, reasoning
        case copyOnSelect = "copy_on_select"
        case fallbackProvider = "fallback_provider"
        case fallbackModel = "fallback_model"
    }

    public init(
        name: String,
        hotkey: String? = nil,
        prompt: String,
        provider: String? = nil,
        model: String,
        reasoning: String? = nil,
        copyOnSelect: Bool? = nil,
        fallbackProvider: String? = nil,
        fallbackModel: String? = nil
    ) {
        self.name = name
        self.hotkey = hotkey
        self.prompt = prompt
        self.provider = provider
        self.model = model
        self.reasoning = reasoning
        self.copyOnSelect = copyOnSelect
        self.fallbackProvider = fallbackProvider
        self.fallbackModel = fallbackModel
    }
}

public struct Config: Codable, Equatable {
    public var providers: [String: ProviderConfig]
    public var defaultProvider: String?
    public var tts: TTSConfig?
    public var commands: [CommandConfig]

    enum CodingKeys: String, CodingKey {
        case providers
        case defaultProvider = "default_provider"
        case tts
        case commands
    }

    public init(
        providers: [String: ProviderConfig],
        defaultProvider: String? = nil,
        tts: TTSConfig? = nil,
        commands: [CommandConfig]
    ) {
        self.providers = providers
        self.defaultProvider = defaultProvider
        self.tts = tts
        self.commands = commands
    }
}

public enum ConfigError: LocalizedError, Equatable {
    case unreadable(String)
    case invalidYAML(String)
    case validation(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "Cannot read config: \(detail)"
        case .invalidYAML(let detail): return "Invalid YAML: \(detail)"
        case .validation(let detail): return detail
        }
    }
}

extension Config {
    public static func parse(yaml: String) throws -> Config {
        var config: Config
        do {
            config = try YAMLDecoder().decode(Config.self, from: yaml)
        } catch let error as DecodingError {
            throw ConfigError.invalidYAML(describe(error))
        } catch {
            throw ConfigError.invalidYAML(error.localizedDescription)
        }
        try config.validate()
        for index in config.commands.indices {
            let providerName = try config.resolveProvider(for: config.commands[index]).name
            config.commands[index].model = ProviderPreset.normalizedModelID(
                config.commands[index].model, providerName: providerName)
            if let fallbackProvider = config.commands[index].fallbackProvider,
               let fallbackModel = config.commands[index].fallbackModel {
                config.commands[index].fallbackModel = ProviderPreset.normalizedModelID(
                    fallbackModel, providerName: fallbackProvider)
            }
        }
        return config
    }

    public func validate() throws {
        guard !providers.isEmpty else {
            throw ConfigError.validation("config.yaml needs at least one entry under providers:")
        }
        if let def = defaultProvider, providers[def] == nil {
            throw ConfigError.validation("default_provider \"\(def)\" is not defined under providers:")
        }
        var seen = Set<String>()
        var seenHotkeys = Set<KeyboardShortcuts.Shortcut>()
        for command in commands {
            guard seen.insert(command.name).inserted else {
                throw ConfigError.validation("Duplicate command name \"\(command.name)\"")
            }
            if command.name.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ConfigError.validation("A command has an empty name")
            }
            _ = try resolveProvider(for: command)
            if let fallback = command.fallbackProvider, providers[fallback] == nil {
                throw ConfigError.validation(
                    "Command \"\(command.name)\" references unknown fallback_provider \"\(fallback)\"")
            }
            if let effort = command.reasoning, !["low", "medium", "high"].contains(effort) {
                throw ConfigError.validation(
                    "Command \"\(command.name)\": reasoning must be low, medium or high")
            }
            if let hotkey = command.hotkey, hotkey.isEmpty == false {
                // Compare parsed shortcuts so "cmd+shift+g" and "shift+cmd+g"
                // count as the same hotkey.
                let shortcut = try HotkeyParser.parse(hotkey)
                guard seenHotkeys.insert(shortcut).inserted else {
                    throw ConfigError.validation(
                        "Command \"\(command.name)\": hotkey \"\(hotkey)\" is already used by another command")
                }
            }
        }
    }

    /// Provider lookup order: explicit per-command, then default_provider,
    /// then the only provider if there is exactly one.
    public func resolveProvider(for command: CommandConfig) throws -> (name: String, provider: ProviderConfig) {
        let name: String
        if let explicit = command.provider {
            name = explicit
        } else if let def = defaultProvider {
            name = def
        } else if providers.count == 1, let only = providers.keys.first {
            name = only
        } else {
            throw ConfigError.validation(
                "Command \"\(command.name)\" needs provider: (or set default_provider:) because several providers are defined")
        }
        guard let provider = providers[name] else {
            throw ConfigError.validation("Command \"\(command.name)\" references unknown provider \"\(name)\"")
        }
        return (name, provider)
    }

    /// Fallback endpoint for a command, or nil when none is configured.
    /// An absent fallback_model reuses the command's primary model.
    public func resolveFallback(for command: CommandConfig) -> (name: String, provider: ProviderConfig, model: String)? {
        guard let name = command.fallbackProvider, let provider = providers[name] else { return nil }
        return (name, provider, command.fallbackModel ?? command.model)
    }

    /// The primary request plus the fallback one, if a fallback is configured.
    public func makeRequests(
        for command: CommandConfig,
        prompt: String,
        system: String? = nil,
        stream: Bool = true,
        timeout: TimeInterval = 300
    ) throws -> (primary: LLMRequest, fallback: LLMRequest?) {
        let (providerName, provider) = try resolveProvider(for: command)
        let primary = LLMRequest(
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            model: command.model,
            prompt: prompt,
            system: system,
            reasoningEffort: command.resolvedReasoning(
                providerName: providerName, model: command.model),
            stream: stream,
            timeout: timeout)
        let fallback = resolveFallback(for: command).map {
            LLMRequest(
                baseURL: $0.provider.baseURL,
                apiKey: $0.provider.apiKey,
                model: $0.model,
                prompt: prompt,
                system: system,
                reasoningEffort: command.resolvedReasoning(
                    providerName: $0.name, model: $0.model),
                stream: stream,
                timeout: timeout)
        }
        return (primary, fallback)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "missing key \"\(key.stringValue)\" at \(path(context))"
        case .typeMismatch(_, let context):
            return "wrong type at \(path(context))"
        case .valueNotFound(_, let context):
            return "missing value at \(path(context))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return String(describing: error)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
        return joined.isEmpty ? "top level" : joined
    }
}
