import Foundation
import Yams

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
    public var baseURL: String?
    public var apiKey: String?
    public var model: String?
    public var voice: String?

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case apiKey = "api_key"
        case model
        case voice
    }

    public init(baseURL: String? = nil, apiKey: String? = nil, model: String? = nil, voice: String? = nil) {
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
    public var temperature: Double?
    public var stream: Bool?
    /// Selecting text in the result window copies it automatically.
    public var copyOnSelect: Bool?

    public var id: String { name }
    public var wantsStream: Bool { stream ?? true }
    public var wantsCopyOnSelect: Bool { copyOnSelect ?? false }

    enum CodingKeys: String, CodingKey {
        case name, hotkey, prompt, provider, model, temperature, stream
        case copyOnSelect = "copy_on_select"
    }

    public init(
        name: String,
        hotkey: String? = nil,
        prompt: String,
        provider: String? = nil,
        model: String,
        temperature: Double? = nil,
        stream: Bool? = nil,
        copyOnSelect: Bool? = nil
    ) {
        self.name = name
        self.hotkey = hotkey
        self.prompt = prompt
        self.provider = provider
        self.model = model
        self.temperature = temperature
        self.stream = stream
        self.copyOnSelect = copyOnSelect
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
        let config: Config
        do {
            config = try YAMLDecoder().decode(Config.self, from: yaml)
        } catch let error as DecodingError {
            throw ConfigError.invalidYAML(describe(error))
        } catch {
            throw ConfigError.invalidYAML(error.localizedDescription)
        }
        try config.validate()
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
        for command in commands {
            guard seen.insert(command.name).inserted else {
                throw ConfigError.validation("Duplicate command name \"\(command.name)\"")
            }
            if command.name.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ConfigError.validation("A command has an empty name")
            }
            _ = try resolveProvider(for: command)
            if let hotkey = command.hotkey, hotkey.isEmpty == false {
                _ = try HotkeyParser.parse(hotkey)
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
