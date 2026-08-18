import Foundation

public enum PromptTemplate {
    /// Fills {selection} and {clipboard}. Unknown placeholders are left as-is
    /// so prompt text about placeholders survives untouched.
    public static func render(_ template: String, selection: String, clipboard: String? = nil) -> String {
        var result = template.replacingOccurrences(of: "{selection}", with: selection)
        if let clipboard {
            result = result.replacingOccurrences(of: "{clipboard}", with: clipboard)
        }
        return result
    }
}
