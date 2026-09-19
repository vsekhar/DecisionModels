import SwiftSyntax

/// The access modifier the generated members copy, with a trailing space.
///
/// Only `public` and `package` travel. A narrower modifier would make a
/// witness less visible than the conformance, and an absent one is right for
/// everything else.
func accessPrefix(of modifiers: DeclModifierListSyntax) -> String {
    for modifier in modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public), .keyword(.open): return "public "
        case .keyword(.package): return "package "
        default: continue
        }
    }
    return ""
}

extension AttributeListSyntax {
    /// The attribute of that name, if the declaration carries it.
    func marker(named name: String) -> AttributeSyntax? {
        for element in self {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            let written = attribute.attributeName.trimmedDescription
            if written == name || written.hasSuffix(".\(name)") { return attribute }
        }
        return nil
    }
}

extension TokenSyntax {
    /// The name as Swift reads it, without the backticks of a raw identifier.
    var plainText: String {
        let written = trimmedDescription
        guard written.hasPrefix("`"), written.hasSuffix("`"), written.count > 1 else {
            return written
        }
        return String(written.dropFirst().dropLast())
    }
}

/// `camelCase` becomes `camel case`, so a case without a `@Criterion` still
/// says something to the model. A run of capitals is a word of its own and
/// keeps its case: `URLIssue` becomes `URL issue`.
func humanized(_ name: String) -> String {
    let letters = Array(name)
    var words: [String] = []
    var word = ""
    for (position, letter) in letters.enumerated() {
        if letter == "_" {
            if !word.isEmpty { words.append(word) }
            word = ""
            continue
        }
        if letter.isUppercase, !word.isEmpty {
            let previous = letters[position - 1]
            let next = position + 1 < letters.count ? letters[position + 1] : nil
            let startsWord = !previous.isUppercase || (next?.isLowercase ?? false)
            if startsWord {
                words.append(word)
                word = ""
            }
        }
        word.append(letter)
    }
    if !word.isEmpty { words.append(word) }
    return words.map { word in
        let acronym = word.count > 1 && word.allSatisfy { !$0.isLowercase }
        return acronym ? word : word.lowercased()
    }.joined(separator: " ")
}
