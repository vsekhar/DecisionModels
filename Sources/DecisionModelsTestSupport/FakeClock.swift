import Synchronization

/// Stands in for the clock, so a test of waits and deadlines runs at full
/// speed. Waiting moves this clock and nothing else, and an attempt moves it
/// by what it spent.
package final class FakeClock: Sendable {
    private struct Ticker: Sendable {
        var now: ContinuousClock.Instant
        var waits: [Duration] = []
    }

    private let start: ContinuousClock.Instant
    private let ticker: Mutex<Ticker>

    package init() {
        let start = ContinuousClock().now
        self.start = start
        self.ticker = Mutex(Ticker(now: start))
    }

    /// Every wait the model asked for, in order.
    package var waited: [Duration] { ticker.withLock { $0.waits } }

    /// How far the clock has moved: the waits and what the attempts spent.
    package var elapsed: Duration { start.duration(to: ticker.withLock { $0.now }) }

    /// Moves the clock without recording a wait.
    package func advance(_ duration: Duration) {
        ticker.withLock { $0.now = $0.now + duration }
    }

    /// The clock to hand the model.
    package var reading: @Sendable () -> ContinuousClock.Instant {
        { self.ticker.withLock { $0.now } }
    }

    /// The wait to hand the model. It records the wait and moves the clock.
    package var record: @Sendable (Duration) async -> Void {
        { duration in
            self.ticker.withLock { ticker in
                ticker.waits.append(duration)
                ticker.now = ticker.now + duration
            }
        }
    }
}

package func isClose(_ value: Double, _ expected: Double, within tolerance: Double = 0.01) -> Bool {
    abs(value - expected) <= tolerance
}
