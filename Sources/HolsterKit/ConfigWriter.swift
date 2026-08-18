import Foundation
import Yams

/// Providers the GUI can create on demand, without hand-editing config.yaml.
public enum ProviderPreset {
    public static let openCodeGo = "opencode-go"
    public static let openCodeGoBaseURL = "https://opencode.ai/zen/go/v1"
    public static let custom = "custom"
}

extension CommandConfig {
    /// Every model OpenCode Go serves today thinks by default, so an absent
    /// reasoning field means full-thinking latency, not "no reasoning" —
    /// fall back to low there instead.
    // ponytail: provider-level heuristic; per-model table if Go adds non-thinkers
    public func resolvedReasoning(providerName: String) -> String? {
        reasoning ?? (providerName == ProviderPreset.openCodeGo ? "low" : nil)
    }
}

/// GUI edits write back to the same files the user can edit by hand.
/// Note: YAML comments do not survive a GUI save (the file is re-serialized).
extension ConfigStore {
    public struct CommandDraft: Equatable {
        public var name: String
        public var hotkey: String
        public var provider: String
        public var model: String
        /// "" = no reasoning field sent; otherwise "low" / "medium" / "high".
        public var reasoning: String
        /// Only written for the opencode-go / custom presets.
        public var baseURL: String
        public var apiKey: String
        public var copyOnSelect: Bool
        public var promptFile: String
        public var promptText: String

        public init(
            name: String = "",
            hotkey: String = "",
            provider: String = "",
            model: String = "",
            reasoning: String = "",
            baseURL: String = "",
            apiKey: String = "",
            copyOnSelect: Bool = false,
            promptFile: String = "",
            promptText: String = ""
        ) {
            self.name = name
            self.hotkey = hotkey
            self.provider = provider
            self.model = model
            self.reasoning = reasoning
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.copyOnSelect = copyOnSelect
            self.promptFile = promptFile
            self.promptText = promptText
        }
    }

    public func draft(for command: CommandConfig) -> CommandDraft {
        let providerName = command.provider ?? config?.defaultProvider ?? ""
        let provider = config?.providers[providerName]
        return CommandDraft(
            name: command.name,
            hotkey: command.hotkey ?? "",
            provider: providerName,
            model: command.model,
            reasoning: command.reasoning ?? "",
            baseURL: provider?.baseURL ?? "",
            apiKey: provider?.apiKey ?? "",
            copyOnSelect: command.wantsCopyOnSelect,
            promptFile: command.prompt,
            promptText: (try? promptText(for: command)) ?? "")
    }

    /// Saves a draft as command `originalName` (nil = new command), writing
    /// both config.yaml and the prompt file.
    public func saveCommand(originalName: String?, draft: CommandDraft) throws {
        guard var config else {
            throw ConfigError.validation("Fix config.yaml before editing commands in the GUI")
        }
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw ConfigError.validation("Command name cannot be empty")
        }
        guard !draft.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConfigError.validation("Model cannot be empty")
        }

        switch draft.provider {
        case ProviderPreset.openCodeGo:
            // ponytail: preset always re-asserts the canonical URL; hand-edits lose.
            config.providers[ProviderPreset.openCodeGo] = ProviderConfig(
                baseURL: ProviderPreset.openCodeGoBaseURL,
                apiKey: draft.apiKey)
        case ProviderPreset.custom:
            let baseURL = draft.baseURL.trimmingCharacters(in: .whitespaces)
            guard !baseURL.isEmpty else {
                throw ConfigError.validation("Custom endpoint needs a base URL (e.g. https://openrouter.ai/api/v1)")
            }
            config.providers[ProviderPreset.custom] = ProviderConfig(
                baseURL: baseURL,
                apiKey: draft.apiKey)
        default:
            break
        }

        let promptFile = draft.promptFile.isEmpty ? slugify(name) + ".md" : draft.promptFile
        let command = CommandConfig(
            name: name,
            hotkey: draft.hotkey.isEmpty ? nil : draft.hotkey,
            prompt: promptFile,
            provider: draft.provider.isEmpty ? nil : draft.provider,
            model: draft.model.trimmingCharacters(in: .whitespaces),
            reasoning: draft.reasoning.isEmpty ? nil : draft.reasoning,
            copyOnSelect: draft.copyOnSelect ? true : nil)

        if let originalName, let index = config.commands.firstIndex(where: { $0.name == originalName }) {
            config.commands[index] = command
        } else {
            config.commands.append(command)
        }
        try config.validate()

        try FileManager.default.createDirectory(at: promptsDirectory, withIntermediateDirectories: true)
        try draft.promptText.write(
            to: promptsDirectory.appendingPathComponent(promptFile),
            atomically: true,
            encoding: .utf8)
        try write(config)
    }

    public func deleteCommand(named name: String) throws {
        guard var config else { return }
        config.commands.removeAll { $0.name == name }
        try write(config)
        // The prompt file stays on disk on purpose; deleting text a user may
        // want back is worse than leaving a stray file.
    }

    private func write(_ config: Config) throws {
        let yaml = try YAMLEncoder().encode(config)
        try yaml.write(to: configFile, atomically: true, encoding: .utf8)
        load()
    }

    private func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        let mapped = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }
}
