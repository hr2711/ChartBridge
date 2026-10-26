import Foundation

enum ChartQuestionIntent: Equatable, Sendable {
    case highest, lowest, total, average, ranking, first, last, netChange, relativeChange
    case trend, largestStep, largestIncrease, largestDecrease, explain
    case difference(Int, Int), relativeDifference(Int, Int), share(Int)
}

enum ChartQuestionClarification: Equatable, Sendable {
    case comparison(relative: Bool), share, oneQuestion
}

enum ChartQuestionResolution: Equatable, Sendable {
    case intent(ChartQuestionIntent), clarify(ChartQuestionClarification), unsupported
}

/// An intentionally bounded English grammar, not a keyword classifier. Extra
/// qualifiers, unknown categories and unsupported causal questions never fall
/// through to an unrelated numerical answer.
enum ChartQuestionParser {
    static let maximumLength = 512

    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".?!")))
            // Keep signs, decimal points and symbols significant in labels:
            // "-1" must never match an unknown "1", nor "A-B" match "A B".
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && !$0.isSymbol && !"-+./%_".contains($0) })
            .joined(separator: " ")
    }

    static func parse(_ question: String, labels: [String]) -> ChartQuestionResolution {
        guard question.count <= maximumLength else { return .unsupported }
        var text = normalized(question)
        for prefix in ["please ", "can you ", "could you ", "tell me ", "show me "] {
            if text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        }
        if text.hasSuffix(" please") { text.removeLast(7) }
        for prefix in ["what is the ", "what s the ", "what is ", "what s "] {
            if text.hasPrefix(prefix) { text.removeFirst(prefix.count); break }
        }
        let simple: [String: ChartQuestionIntent] = [
            "total": .total, "sum": .total, "total value": .total, "sum of the values": .total,
            "average": .average, "mean": .average, "average value": .average,
            "rank the categories": .ranking, "rank categories": .ranking, "ranking": .ranking,
            "rank the segments": .ranking, "rank the values": .ranking,
            "first value": .first, "start value": .first, "starting value": .first,
            "last value": .last, "end value": .last, "ending value": .last,
            "overall change": .netChange, "net change": .netChange, "how much did the value increase": .netChange,
            "how much did the value decrease": .netChange, "how much did it change": .netChange,
            "percentage change": .relativeChange, "percent change": .relativeChange,
            "overall percentage change": .relativeChange, "overall trend": .trend, "trend": .trend,
            "how did the values change": .trend, "does the chart go up or down": .trend,
            "which point changed the most": .largestStep, "largest change": .largestStep,
            "largest increase": .largestIncrease, "largest decrease": .largestDecrease,
            "explain this chart simply": .explain, "explain this chart": .explain,
            "explain the chart": .explain, "simple explanation": .explain, "what does this chart show": .explain
        ]
        if let intent = simple[text] { return .intent(intent) }
        if text == "share of" || text == "segment share" { return .clarify(.share) }
        for (words, intent) in [(["highest", "largest", "biggest", "most"], ChartQuestionIntent.highest),
                                (["lowest", "smallest", "least"], ChartQuestionIntent.lowest)] {
            for word in words {
                if text == word || text == "\(word) value" { return .intent(intent) }
                for noun in ["category", "segment", "point", "value"] {
                    if ["which \(noun) is \(word)", "which \(noun) is the \(word)",
                        "which \(noun) has the \(word) value", "which \(noun) has the \(word)"] .contains(text) {
                        return .intent(intent)
                    }
                }
            }
        }
        if ["highest and lowest", "highest and lowest values", "which category is highest and lowest"].contains(text) {
            return .clarify(.oneQuestion)
        }
        for prefix in ["percentage change from ", "percent change from ", "relative change from ", "percentage difference from "] {
            if text.hasPrefix(prefix) {
                return pair(String(text.dropFirst(prefix.count)), separators: [" to "], labels: labels, relative: true)
            }
        }
        for prefix in ["percentage difference between ", "percent difference between "] {
            if text.hasPrefix(prefix) { return .clarify(.comparison(relative: true)) }
        }
        for prefix in ["difference between ", "compare "] {
            if text.hasPrefix(prefix) {
                return pair(String(text.dropFirst(prefix.count)), separators: [" and ", " with ", " versus ", " vs ", " to "], labels: labels, relative: false)
            }
        }
        for (prefix, suffix) in [("what percentage does ", " represent"), ("what share does ", " represent"),
                                 ("percentage for ", ""), ("share of ", ""), ("percentage of ", "")] {
            if text.hasPrefix(prefix), text.hasSuffix(suffix) {
                let slot = String(text.dropFirst(prefix.count).dropLast(suffix.count))
                let matches = labels.indices.filter { normalized(labels[$0]) == slot }
                return matches.count == 1 ? .intent(.share(matches[0])) : .clarify(.share)
            }
        }
        return .unsupported
    }

    private static func pair(_ body: String, separators: [String], labels: [String], relative: Bool) -> ChartQuestionResolution {
        let names = labels.map(normalized)
        var pairs: [[Int]] = []
        // Try every boundary: a category can itself contain "and" or "to".
        for separator in separators {
            var search = body.startIndex..<body.endIndex
            while let range = body.range(of: separator, range: search) {
                let left = String(body[..<range.lowerBound]), right = String(body[range.upperBound...])
                for a in names.indices where names[a] == left {
                    for b in names.indices where names[b] == right {
                        if !pairs.contains([a, b]) { pairs.append([a, b]) }
                    }
                }
                search = range.upperBound..<body.endIndex
            }
        }
        guard pairs.count == 1 else { return .clarify(.comparison(relative: relative)) }
        let pair = pairs[0]
        return .intent(relative ? .relativeDifference(pair[0], pair[1]) : .difference(pair[0], pair[1]))
    }
}
