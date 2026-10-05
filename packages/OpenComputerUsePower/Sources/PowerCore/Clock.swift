import Darwin

public enum PowerClock {
    /// Continuous monotonic time: unaffected by wall-clock changes, includes time asleep.
    public static var now: Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000 }
}
