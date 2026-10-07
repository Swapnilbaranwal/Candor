import SwiftUI

/// In-app language switch.
///
/// The traveller picks a language inside Candor, and it need not be the phone's language, so
/// strings are looked up in a bundled table per language (`Localization/candor-<code>.json`)
/// instead of following the system locale. The English string is the key; a key missing from
/// a table falls back to English, so a new string never breaks the screen.
@Observable
final class Localizer {
    static let shared = Localizer()

    private(set) var language = "en"
    private(set) var table: [String: String] = [:]

    private static let rightToLeft: Set<String> = ["ar", "he"]

    var locale: Locale { Locale(identifier: language) }

    var layoutDirection: LayoutDirection {
        Self.rightToLeft.contains(language) ? .rightToLeft : .leftToRight
    }

    /// "From → to" arrow that points the reading way (arrows are not mirrored automatically).
    var arrow: String { layoutDirection == .rightToLeft ? "←" : "→" }

    /// Switches the app to `code` ("ja", "es"…). English, or a language with no table, shows English.
    func use(_ code: String) {
        guard code != language else { return }
        language = code
        table = Self.load(code)
    }

    private static func load(_ code: String) -> [String: String] {
        guard code != "en" else { return [:] }
        let name = "candor-\(code)"
        let url = Bundle.main.url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Localization")
        guard let url,
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return table
    }

    func string(_ key: String, _ args: [String]) -> String {
        let template = table[key] ?? key
        return args.isEmpty ? template : Self.fill(template, with: args)
    }

    /// Replaces `%@` (in order) and `%1$@`, `%2$@`… (by position) with `args` in one pass.
    /// Any other `%` is left alone, so text like "+25%" needs no escaping.
    private static func fill(_ template: String, with args: [String]) -> String {
        var output = ""
        var sequential = 0
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            guard character == "%" else {
                output.append(character)
                index = template.index(after: index)
                continue
            }

            var cursor = template.index(after: index)
            var number = ""
            while cursor < template.endIndex, template[cursor].isASCII, template[cursor].isNumber {
                number.append(template[cursor])
                cursor = template.index(after: cursor)
            }
            let hasDollar = cursor < template.endIndex && template[cursor] == "$"
            if hasDollar { cursor = template.index(after: cursor) }

            let isPlaceholder = cursor < template.endIndex
                && template[cursor] == "@"
                && number.isEmpty != hasDollar
            guard isPlaceholder else {
                output.append(character)
                index = template.index(after: index)
                continue
            }

            let position: Int
            if number.isEmpty {
                position = sequential
                sequential += 1
            } else {
                position = (Int(number) ?? 1) - 1
            }
            if args.indices.contains(position) { output += args[position] }
            index = template.index(after: cursor)
        }
        return output
    }
}

/// Localized text in the language chosen in the app.
///
///     L("Sign in")
///     L("Days in Delhi: %@", days)
///     L("%1$@ to %2$@", vehicle, place)
///     L(scam.title)            // data strings are keys too
func L(_ key: String, _ args: any CustomStringConvertible...) -> String {
    Localizer.shared.string(key, args.map { $0.description })
}
