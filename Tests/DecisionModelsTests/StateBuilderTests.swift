import Testing

@testable import DecisionModels

@Suite("State builder")
struct StateBuilderTests {
    func state(@StateBuilder _ build: () throws -> State) rethrows -> State {
        try build()
    }

    @Test("Fields become one object")
    func fieldsBecomeAnObject() {
        let built = state {
            Field("message", "The order never arrived.")
            Field("orders", 3)
            Field("vip", true)
            Field("scores", [1.5, 2.5])
        }
        #expect(built == .object([
            "message": .text("The order never arrived."),
            "orders": .number(3),
            "vip": .bool(true),
            "scores": .array([.number(1.5), .number(2.5)]),
        ]))
    }

    @Test("The builder takes if let and try")
    func builderTakesIfLetAndTry() throws {
        let order: Customer? = Customer(name: "Ada", orders: 3, vip: true)
        let missing: Customer? = nil

        let built = try state {
            Field("message", "Where is my order?")
            if let order {
                try Field("customer", encoding: order)
            }
            if let missing {
                try Field("absent", encoding: missing)
            }
        }
        #expect(built == .object([
            "message": .text("Where is my order?"),
            "customer": .object([
                "name": .text("Ada"),
                "orders": .number(3),
                "vip": .bool(true),
            ]),
        ]))
    }

    @Test("The builder takes if, else, and for")
    func builderTakesConditionsAndLoops() {
        let urgent = true
        let built = state {
            if urgent {
                Field("priority", "high")
            } else {
                Field("priority", "normal")
            }
            for (index, skill) in catalog.enumerated() {
                Field("skill\(index)", skill.summary)
            }
        }
        #expect(built == .object([
            "priority": .text("high"),
            "skill0": .text("Find something"),
            "skill1": .text("Give money back"),
            "skill2": .text("Hand to a person"),
        ]))
    }

    @Test("A field can hold state of its own")
    func fieldTakesState() {
        let built = state {
            Field("nested", State.object(["a": .number(1)]))
            Field("list", ["x": "y"])
        }
        #expect(built == .object([
            "nested": .object(["a": .number(1)]),
            "list": .object(["x": .text("y")]),
        ]))
    }
}
