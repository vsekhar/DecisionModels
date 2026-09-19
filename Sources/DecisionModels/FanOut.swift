import Foundation

/// One yes or no answer per option: what a `Set` property holds.
///
/// A `Set` question fans out into one verdict per case. See DESIGN.md
/// section 16.
public struct FanOut<Option: ChoiceOption & CaseIterable>: Sendable {
    /// The answer for every option the model judged.
    public let verdicts: [Option: Verdict]

    public init(verdicts: [Option: Verdict]) {
        self.verdicts = verdicts
    }

    /// The answer for one option. An option with no answer says nothing.
    public subscript(option: Option) -> Verdict {
        verdicts[option] ?? .uncertain
    }

    /// The options whose probability reaches the bar.
    public func members(atLeast probability: Double) -> Set<Option> {
        Set(verdicts.filter { $0.value.probability >= probability }.keys)
    }

    /// How much the probabilities can be trusted: the weakest over every
    /// case. A case with no verdict counts as a point estimate, so a
    /// partial fan-out never claims more than it holds.
    public var quality: ProbabilityQuality {
        Option.allCases.map { self[$0].quality }.min() ?? .calibrated
    }
}

extension FanOut: Codable where Option: Codable {}

// MARK: Fan-out

/// A set asks one yes or no question per case: does this option belong?
///
/// Every question takes the id `"\(id).\(optionID)"`, and `{option}` in the
/// instructions becomes the case's criterion summary.
extension Set: Askable where Element: ChoiceOption & CaseIterable {
    public typealias Projection = FanOut<Element>

    public static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
        Element.allCases.map { option in
            Verify(
                "\(id).\(option.optionID)",
                inquiry.instructions.namingOption(option.criterion.summary),
                ifTrue: inquiry.ifTrue,
                ifFalse: inquiry.ifFalse
            ).spec
        }
    }

    public static func projection(in answers: Answers, id: String) throws -> FanOut<Element> {
        var verdicts: [Element: Verdict] = [:]
        for option in Element.allCases {
            verdicts[option] = try answers.verdict("\(id).\(option.optionID)")
        }
        return FanOut(verdicts: verdicts)
    }

    public static func read(_ projection: FanOut<Element>) -> Set<Element> {
        projection.members(atLeast: 0.5)
    }

    /// The members the model is sure enough about. Only a set has this
    /// two-argument read, so a `minimumProbability` on any other property
    /// fails to type-check, which is the diagnostic we want.
    public static func read(
        _ projection: FanOut<Element>,
        minimumProbability: Double
    ) -> Set<Element> {
        projection.members(atLeast: minimumProbability)
    }

    public static func answers(from projection: FanOut<Element>, id: String) -> Answers {
        var records: [String: AnswerRecord] = [:]
        for option in Element.allCases {
            records["\(id).\(option.optionID)"] = projection[option].record
        }
        return Answers(records: records, quality: projection.quality)
    }

    /// The answer a plain set stands for: yes for a member, no for the rest.
    public static func certain(_ value: Set<Element>) -> FanOut<Element> {
        var verdicts: [Element: Verdict] = [:]
        for option in Element.allCases {
            verdicts[option] = Verdict(certain: value.contains(option))
        }
        return FanOut(verdicts: verdicts)
    }
}

extension State {
    /// Puts one option's summary where the instructions say `{option}`.
    ///
    /// Every string leaf takes the substitution, so structured instructions
    /// name the option wherever they mention it. Other leaves stay as they are.
    fileprivate func namingOption(_ summary: String) -> State {
        switch self {
        case .text(let text):
            .text(text.replacingOccurrences(of: "{option}", with: summary))
        case .array(let values):
            .array(values.map { $0.namingOption(summary) })
        case .object(let fields):
            .object(fields.mapValues { $0.namingOption(summary) })
        case .number, .bool, .null:
            self
        }
    }
}
