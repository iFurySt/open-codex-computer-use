import Foundation

/// Millisecond timing for the background-input and window-placement paths.
/// Enabled with `OPEN_COMPUTER_USE_DEBUG_TIMING=1`; lines go to stderr as
/// `[open-computer-use] timing <label> <ms>ms` so a tool session can be
/// profiled without changing tool output.
enum TimingLog {
    nonisolated(unsafe) static var enabled: Bool = {
        let value = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_DEBUG_TIMING"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["1", "true", "yes", "on"].contains(value)
    }()

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func log(_ label: String, since start: TimeInterval) {
        guard enabled else { return }
        fputs(String(format: "[open-computer-use] timing %@ %.1fms\n", label, (now() - start) * 1000), stderr)
    }

    static func measure<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let start = now()
        defer { log(label, since: start) }
        return try body()
    }
}

/// Calibration knobs for the fixed gaps in the input recipes. Every gap
/// defaults to the value verified by the benchmark on macOS 27 and can be
/// overridden per environment (milliseconds) when a target needs more slack.
enum InputTiming {
    static let typeChunkDelayDefaultMilliseconds = 20.0
    static let pressKeySettleDefaultMilliseconds = 100.0

    static func milliseconds(
        _ variable: String,
        default fallback: Double,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        guard let raw = environment[variable], let ms = Double(raw) else { return fallback / 1000 }
        return max(0, ms) / 1000
    }

    // Benchmark on macOS 27 (30-50 cycles each, covered Chrome, exact-once
    // clicks): focus settle 0 ms and click scale 0.05 still pass; click scale 0
    // fails every click and poisons the next key cycle. Defaults keep a 2x
    // margin over the passing minimum. Focus records and CGEvents travel
    // different channels, which is why a small gap between them stays.
    /// Gap after a synthetic focus / defocus record (sky_click and sky_key). Was 40 ms.
    static let focusRecordSettle = milliseconds("OPEN_COMPUTER_USE_FOCUS_RECORD_SETTLE_MS", default: 10)
    /// Multiplier for the sky_click recipe gaps (move/primer/click pairs) and the renderer settle. Was 1.
    static let skyClickDelayScale: Double = {
        guard let raw = ProcessInfo.processInfo.environment["OPEN_COMPUTER_USE_SKY_CLICK_DELAY_SCALE"], let scale = Double(raw) else { return 0.2 }
        return max(0, scale)
    }()
    /// Gap between Unicode chunks in type_text. Keep the established default for
    /// app/toolkit compatibility; callers can explicitly tune it after testing.
    static let typeChunkDelay = milliseconds(
        "OPEN_COMPUTER_USE_TYPE_CHUNK_DELAY_MS",
        default: typeChunkDelayDefaultMilliseconds
    )
    /// Gap after a press_key chord. Keep the established default because the
    /// target may process its event queue asynchronously.
    static let pressKeySettle = milliseconds(
        "OPEN_COMPUTER_USE_PRESS_KEY_SETTLE_MS",
        default: pressKeySettleDefaultMilliseconds
    )
}

/// Poll `condition` every `interval` until it holds or `timeout` elapses.
/// Returns the elapsed time when it held, or nil on timeout.
@discardableResult
func waitUntil(timeout: TimeInterval, interval: TimeInterval = 0.01, _ condition: () -> Bool) -> TimeInterval? {
    let start = TimingLog.now()
    while TimingLog.now() - start < timeout {
        if condition() {
            return TimingLog.now() - start
        }
        Thread.sleep(forTimeInterval: interval)
    }
    return nil
}
