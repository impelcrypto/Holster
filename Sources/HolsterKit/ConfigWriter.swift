import Foundation
import Yams

/// GUI edits write back to the same files the user can edit by hand.
/// Note: YAML comments do not survive a GUI save (the file is re-serialized).
extension ConfigStore {
    public struct CommandDraft {
        public var name: String
        public var hotkey: String
        public var provider: String
        public var model: String
        public var temperatureText: String
        public var stream: Bool
        public var copyOnSelect: Bool
        public var promptFile: String
        public var promptText: String

        public init(
            name: String = "",
            hotkey: String = "",
            provider: String = "",
            model: String = "",
            temperatureText: String = "",
            stream: Bool = true,
            copyOnSelect: Bool = false,
            promptFile: String = "",
            promptText: String = ""
        ) {
            self.name = name
            self.hotkey = hotkey
            self.provider = provider
            self.model = model
            self.temperatureText = temperatureText
            self.stream = stream
            self.copyOnSelect = copyOnSelect
            self.promptFile = promptFile
            self.promptText = promptText
        }
    }

    public func draft(for command: CommandConfig) -> CommandDraft {
        CommandDraft(
            name: command.name,
            hotkey: command.hotkey ?? "",
            provider: command.provider ?? config?.defaultProvider ?? "",
            model: command.model,
            temperatureText: command.temperature.map { formatTemperature($0) } ?? "",
            stream: command.wantsStream,
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

        let temperature: Double?
        let trimmedTemperature = draft.temperatureText.trimmingCharacters(in: .whitespaces)
        if trimmedTemperature.isEmpty {
            temperature = nil
        } else if let value = Double(trimmedTemperature) {
            temperature = value
        } else {
            throw ConfigError.validation("Temperature must be a number (or empty for the provider default)")
        }

        let promptFile = draft.promptFile.isEmpty ? slugify(name) + ".md" : draft.promptFile
        let command = CommandConfig(
            name: name,
            hotkey: draft.hotkey.isEmpty ? nil : draft.hotkey,
            prompt: promptFile,
            provider: draft.provider.isEmpty ? nil : draft.provider,
            model: draft.model.trimmingCharacters(in: .whitespaces),
            temperature: temperature,
            stream: draft.stream ? nil : false,
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

    private func formatTemperature(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
