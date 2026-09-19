import Testing

@testable import DecisionModels

@Suite("Questionnaire")
struct QuestionnaireTests {
    @Test("The builder collects question values")
    func builderCollectsQuestions() {
        let skill = Choose("skill", "Which skill fits the request?", among: catalog)
        let effort = Rate<Severity>("effort", "How much work is the request?")
        let unsafe = Verify("unsafe", "Does the request break the policy?")

        let questionnaire = Questionnaire { skill; effort; unsafe }
        #expect(questionnaire.specs.map(\.id) == ["skill", "effort", "unsafe"])
    }

    @Test("The builder takes conditions and loops")
    func builderTakesConditionsAndLoops() {
        let includeEffort = false
        let questionnaire = Questionnaire {
            Choose("team", "Which team handles this ticket?", among: Array(Team.allCases))
            if includeEffort {
                Rate<Severity>("effort", "How much work is the request?")
            }
            for skill in catalog {
                Verify("fits.\(skill.id)", .text("Does \(skill.summary) fit?"))
            }
        }
        #expect(questionnaire.specs.map(\.id) == [
            "team", "fits.search", "fits.refund", "fits.escalate",
        ])
    }

    @Test("A question value carries its own wire form")
    func specsMatchTheQuestions() {
        let skill = Choose("skill", "Which skill fits the request?", among: catalog)
        guard case .choice(let options) = skill.spec.kind else {
            Issue.record("The kind is not a choice.")
            return
        }
        #expect(options.map(\.id) == ["search", "refund", "escalate"])
        #expect(options.first?.criterion.summary == "Find something")
        #expect(skill.spec.instructions == .text("Which skill fits the request?"))

        let severity = Rate<Severity>("severity", "How severe is the issue?")
        guard case .rating(let levels) = severity.spec.kind else {
            Issue.record("The kind is not a rating.")
            return
        }
        #expect(levels.map(\.summary) == Severity.allCases.map(\.criterion.summary))

        let refund = Verify(
            "refund",
            ["question": "Does the customer ask for a refund?"],
            ifTrue: "Wants money back",
            ifFalse: "Wants a fix"
        )
        guard case .verdict(let ifTrue, let ifFalse) = refund.spec.kind else {
            Issue.record("The kind is not a verdict.")
            return
        }
        #expect(ifTrue == Criterion("Wants money back"))
        #expect(ifFalse == Criterion("Wants a fix"))
        #expect(refund.spec.instructions == .object(
            ["question": .text("Does the customer ask for a refund?")]
        ))
    }

    @Test("A choice over an enum needs no option list")
    func caseIterableInitializer() {
        let team = Choose<Team>("team", "Which team handles this ticket?")
        #expect(team.options == Array(Team.allCases))
    }

    @Test("A prefix renames every question")
    func prefixedRenamesQuestions() {
        var questionnaire = Questionnaire()
        questionnaire.add(Rate<Severity>("severity", "How severe is the issue?"))
        questionnaire.add(Verify("reproducible", "Can the issue be reproduced?"))

        let nested = questionnaire.prefixed("bug")
        #expect(nested.specs.map(\.id) == ["bug.severity", "bug.reproducible"])
        #expect(nested.specs.map(\.kind) == questionnaire.specs.map(\.kind))
    }
}
