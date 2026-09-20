import DecisionModels
import DecisionModelsTestSupport
import Foundation

@testable import DecisionModelsOpenRouter

// The fixture is OpenRouter's documented example, so the wire tests compare
// against the docs and the live test checks the answer the docs show.

/// The ticket from the documented example.
let ticket: State =
    "My checkout page shows a blank screen after I click Pay. I have tried two browsers."

/// The three questions from the documented example: a noul with both sides,
/// a choice with three options, and a score with three levels.
func triage() -> Questionnaire {
    Questionnaire([
        QuestionSpec(
            id: "is_bug",
            instructions: "Is the customer reporting a software defect?",
            kind: .verdict(
                ifTrue: "The customer describes broken or unexpected product behavior.",
                ifFalse: "The customer is asking a question or requesting a feature."
            )
        ),
        QuestionSpec(
            id: "team",
            instructions: "Which team should own this ticket?",
            kind: .choice(options: [
                QuestionSpec.OptionSpec(
                    id: "account", criterion: "Login, permissions, or profile issues."
                ),
                QuestionSpec.OptionSpec(
                    id: "frontend",
                    criterion: "Rendering, layout, or browser compatibility issues."
                ),
                QuestionSpec.OptionSpec(
                    id: "payments", criterion: "Checkout, billing, or payment processing issues."
                ),
            ])
        ),
        QuestionSpec(
            id: "urgency",
            instructions: "How urgent is this ticket?",
            kind: .rating(levels: [
                "Can wait for the next release",
                "Should be fixed this week",
                "Blocking revenue right now",
            ])
        ),
    ])
}

/// The documented request body for `triage()` against `typesafe/jev-1.13`.
let documentedRequest = """
    {
      "model": "typesafe/jev-1.13",
      "questions": {
        "is_bug": {
          "type": "noul",
          "instructions": "Is the customer reporting a software defect?",
          "criteria": {
            "true": "The customer describes broken or unexpected product behavior.",
            "false": "The customer is asking a question or requesting a feature."
          }
        },
        "team": {
          "type": "choice",
          "instructions": "Which team should own this ticket?",
          "criteria": {
            "account": "Login, permissions, or profile issues.",
            "frontend": "Rendering, layout, or browser compatibility issues.",
            "payments": "Checkout, billing, or payment processing issues."
          }
        },
        "urgency": {
          "type": "score",
          "instructions": "How urgent is this ticket?",
          "criteria": [
            "Can wait for the next release",
            "Should be fixed this week",
            "Blocking revenue right now"
          ]
        }
      },
      "state": "My checkout page shows a blank screen after I click Pay. I have tried two browsers."
    }
    """

/// The documented reply, with one answer of each kind and a cost in usage.
let documentedResponse = """
    {
      "id": "gen-dec-1789738314-X5e5eKGQdvR9rblyX250",
      "model": "typesafe/jev-1.13-20260917",
      "provider": "TypeSafe",
      "answers": {
        "is_bug": { "type": "noul", "noul": 0.96 },
        "team": {
          "type": "choice", "choice": "payments", "confidence": 0.75,
          "probabilities": { "account": 0, "frontend": 0.16, "payments": 0.84 }
        },
        "urgency": {
          "type": "score", "score": 1.99, "confidence": 0.99,
          "legend": {
            "0": "Can wait for the next release",
            "1": "Should be fixed this week",
            "2": "Blocking revenue right now"
          },
          "probabilities": { "0": 0, "1": 0.01, "2": 0.99 }
        }
      },
      "usage": { "input_tokens": 476, "output_tokens": 70, "cost": 0.000019992 }
    }
    """

/// A model, its transport, and its clock, wired together.
struct Harness {
    var model: OpenRouterAlpha
    var transport: ScriptedTransport
    var clock: FakeClock
}

/// Builds a model that talks to a script instead of the network.
func harness(
    _ replies: [Reply],
    retry: RetryPolicy = .default,
    apiKey: String? = "test-key",
    model: String = "typesafe/jev-1.13",
    environment: [String: String] = [:]
) -> Harness {
    let clock = FakeClock()
    let transport = ScriptedTransport(replies, clock: clock)
    let model = OpenRouterAlpha(
        model: model,
        apiKey: apiKey,
        retry: retry,
        transport: transport,
        environment: environment,
        sleep: clock.record,
        now: clock.reading
    )
    return Harness(model: model, transport: transport, clock: clock)
}
