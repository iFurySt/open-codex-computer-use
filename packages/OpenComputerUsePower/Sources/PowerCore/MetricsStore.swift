import Foundation
import Darwin
import CSQLite
import PowerNative

public final class MetricsStore {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    public static var defaultPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenComputerUsePower" + PowerPaths.suffix + "/Metrics/metrics.sqlite3").path
    }
    public init(path: String = MetricsStore.defaultPath) throws {
        if path != ":memory:" {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(directory, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0, ocu_power_no_extended_acl(directory) == 0 else { throw PowerFailure.backend("Unsafe metrics directory") }
            let file = open(path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
            guard file >= 0 else { throw PowerFailure.backend("Cannot open metrics file") }
            defer { close(file) }
            guard fstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_nlink == 1, ocu_power_no_extended_acl(path) == 0 else { throw PowerFailure.backend("Unsafe metrics file") }
            for suffix in ["-wal", "-shm", "-journal"] {
                if lstat(path + suffix, &info) == 0 {
                    guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_nlink == 1, ocu_power_no_extended_acl(path + suffix) == 0 else { throw PowerFailure.backend("Unsafe metrics sidecar") }
                } else if errno != ENOENT { throw PowerFailure.backend("Cannot inspect metrics sidecar") }
            }
        }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { if let db { sqlite3_close(db) }; db = nil; throw PowerFailure.backend("Cannot open metrics SQLite database") }
        do {
            sqlite3_busy_timeout(db, 1000)
            let schema = try scalar("PRAGMA user_version")
            guard schema <= 1 else { throw PowerFailure.backend("Unsupported metrics schema version") }
            try execute("PRAGMA page_size=4096; PRAGMA secure_delete=ON; PRAGMA journal_mode=DELETE;")
            let pageSize = try scalar("PRAGMA page_size")
            guard pageSize > 0 else { throw PowerFailure.backend("Invalid SQLite page size") }
            let maximumPages = 32 * 1024 * 1024 / pageSize
            guard try scalar("PRAGMA page_count") <= maximumPages else { throw PowerFailure.backend("Metrics database exceeds 32 MiB") }
            try execute("PRAGMA max_page_count=\(maximumPages)")
            // DELETE journal avoids a retained unbounded WAL; database allocation <=32 MiB.
            try execute("CREATE TABLE IF NOT EXISTS samples(id INTEGER PRIMARY KEY, timestamp REAL NOT NULL, payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS samples_time ON samples(timestamp); CREATE TABLE IF NOT EXISTS settings(id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL); PRAGMA user_version=1")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { if let db { sqlite3_close(db) } }
    private func failure() -> Error { PowerFailure.backend("Metrics SQLite operation failed (code \(sqlite3_errcode(db)))") }
    private func execute(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() } }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK, let result else { throw failure() }
        return result
    }
    private func scalar(_ sql: String) throws -> Int {
        let s = try statement(sql); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_ROW else { throw failure() }
        return Int(sqlite3_column_int64(s, 0))
    }
    private func bind(_ data: Data, to statement: OpaquePointer, at index: Int32) throws {
        let text = String(decoding: data, as: UTF8.self)
        guard sqlite3_bind_text(statement, index, text, -1, transient) == SQLITE_OK else { throw failure() }
    }
    private func rowData(_ statement: OpaquePointer, at index: Int32) throws -> Data {
        guard sqlite3_column_bytes(statement, index) <= 8192, let text = sqlite3_column_text(statement, index) else { throw PowerFailure.backend("Invalid metrics row") }
        return Data(bytes: text, count: Int(sqlite3_column_bytes(statement, index)))
    }
    public func configuration() throws -> MetricsConfiguration {
        lock.lock(); defer { lock.unlock() }
        let s = try statement("SELECT payload FROM settings WHERE id=1"); defer { sqlite3_finalize(s) }
        let code = sqlite3_step(s)
        if code == SQLITE_DONE { return .init() }
        guard code == SQLITE_ROW else { throw failure() }
        let config = try JSONDecoder().decode(MetricsConfiguration.self, from: rowData(s, at: 0)); try config.validate(); return config
    }
    public func configure(_ value: MetricsConfiguration, now: Double) throws {
        try value.validate(); lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let s = try statement("INSERT OR REPLACE INTO settings(id,payload) VALUES(1,?)"); defer { sqlite3_finalize(s) }
            try bind(JSONEncoder().encode(value), to: s, at: 1)
            guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
            try prune(now: now, retention: value.retention_seconds)
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func append(_ sample: MetricsSample, now: Double, retention: Double) throws {
        guard sample.timestamp.isFinite, sample.uptime_seconds.isFinite else { throw PowerFailure.invalid("Invalid metrics timestamp") }
        let payload = try JSONEncoder().encode(sample)
        guard payload.count <= 8192 else { throw PowerFailure.invalid("Metrics sample exceeds 8 KiB") }
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            // Prune before insertion so reaching the allocation cap remains recoverable.
            try prune(now: now, retention: retention)
            let s = try statement("INSERT INTO samples(timestamp,payload) VALUES(?,?)"); defer { sqlite3_finalize(s) }
            sqlite3_bind_double(s, 1, sample.timestamp); try bind(payload, to: s, at: 2)
            guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
            try execute("DELETE FROM samples WHERE id < (SELECT id FROM samples ORDER BY id DESC LIMIT 1 OFFSET 9999); COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func prune(now: Double, retention: Double) throws {
        guard now.isFinite, retention.isFinite, retention > 0 else { throw PowerFailure.invalid("Invalid retention") }
        lock.lock(); defer { lock.unlock() }
        // Future samples are removed after wall-clock rollback rather than living indefinitely.
        let s = try statement("DELETE FROM samples WHERE timestamp < ? OR timestamp > ?"); defer { sqlite3_finalize(s) }
        sqlite3_bind_double(s, 1, now - retention); sqlite3_bind_double(s, 2, now + 1)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    public func query(_ query: MetricsQuery) throws -> (samples: [MetricsSample], truncated: Bool) {
        try query.validate(); lock.lock(); defer { lock.unlock() }
        let s = try statement("SELECT payload FROM samples WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp DESC, id DESC LIMIT ?")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_double(s, 1, query.since ?? -Double.greatestFiniteMagnitude)
        sqlite3_bind_double(s, 2, query.until ?? Double.greatestFiniteMagnitude)
        sqlite3_bind_int(s, 3, Int32(query.limit + 1))
        var result: [MetricsSample] = []
        while true {
            let code = sqlite3_step(s); if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw failure() }
            result.append(try JSONDecoder().decode(MetricsSample.self, from: rowData(s, at: 0)))
        }
        let truncated = result.count > query.limit
        if truncated { result.removeLast() }
        return (result.reversed(), truncated)
    }
    public func clear() throws { lock.lock(); defer { lock.unlock() }; try execute("DELETE FROM samples; VACUUM") }
}
