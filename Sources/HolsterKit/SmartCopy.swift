import Foundation

/// Pulls the one sentence worth pasting out of a grammar-check response:
/// the corrected sentence, or the Natural Rephrase when nothing needed
/// correcting. Returns nil when no such sentence exists.
public enum SmartCopy {
    private static let noCorrections = "No grammar corrections needed."

    public static func extract(from markdown: String) -> String? {
        let paragraphs = split(markdown)
        let candidates = paragraphs.filter { !isStructural($0) }
        guard let first = candidates.first else { return nil }

        if normalize(first) == normalize(noCorrections) {
            guard let rephrase = rephraseParagraph(in: paragraphs) else { return nil }
            return stripEmphasis(rephrase)
        }
        if let inline = stripRephraseLabel(first), inline.isEmpty {
            // First candidate is just the "Natural Rephrase:" label.
            guard let index = candidates.dropFirst().firstIndex(where: { !isLabel($0) }) else { return nil }
            return stripEmphasis(candidates[index])
        }
        return stripEmphasis(stripRephraseLabel(first) ?? first)
    }

    // MARK: - Internals

    private static func split(_ markdown: String) -> [String] {
        markdown
            .components(separatedBy: "\n\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .reduce(into: [String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return }
                // Table rows and heading/divider lines never join a paragraph.
                result.append(trimmed)
            }
    }

    private static func isStructural(_ line: String) -> Bool {
        line.hasPrefix("|") || line.hasPrefix("#") || line.hasPrefix("---")
    }

    private static func isLabel(_ line: String) -> Bool {
        normalize(line) == "natural rephrase:"
    }

    private static func rephraseParagraph(in lines: [String]) -> String? {
        guard let labelIndex = lines.firstIndex(where: isLabel) else { return nil }
        return lines.dropFirst(labelIndex + 1).first { !isStructural($0) && !isLabel($0) }
    }

    private static func stripRephraseLabel(_ line: String) -> String? {
        let lowered = line.lowercased()
        guard lowered.hasPrefix("natural rephrase:") else { return nil }
        return String(line.dropFirst("natural rephrase:".count))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func normalize(_ line: String) -> String {
        line.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Removes *emphasis* asterisks outside `code spans`; underscores stay
    /// because identifiers like marketType_v2 must survive.
    static func stripEmphasis(_ text: String) -> String {
        var result = ""
        var inCode = false
        for character in text {
            if character == "`" {
                inCode.toggle()
                result.append(character)
            } else if character == "*" && !inCode {
                continue
            } else {
                result.append(character)
            }
        }
        return result
    }
}
