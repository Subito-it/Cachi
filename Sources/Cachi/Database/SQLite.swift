import Foundation
import os
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A value that can be bound to a prepared statement or read from a row.
enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    init(_ value: Bool) {
        self = .integer(value ? 1 : 0)
    }

    init(_ value: Date) {
        self = .real(value.timeIntervalSince1970)
    }

    init(_ value: String?) {
        self = value.map { .text($0) } ?? .null
    }

    init(_ value: Int?) {
        self = value.map { .integer(Int64($0)) } ?? .null
    }

    init(_ value: Date?) {
        self = value.map { .real($0.timeIntervalSince1970) } ?? .null
    }
}

/// A single result row, addressable by column index.
struct SQLiteRow {
    private let columns: [SQLiteValue]
    private let indexByName: [String: Int]

    init(columns: [SQLiteValue], indexByName: [String: Int]) {
        self.columns = columns
        self.indexByName = indexByName
    }

    func value(_ name: String) -> SQLiteValue {
        guard let index = indexByName[name] else { return .null }
        return columns[index]
    }

    func string(_ name: String) -> String? {
        if case let .text(value) = value(name) { return value }
        return nil
    }

    func int(_ name: String) -> Int? {
        if case let .integer(value) = value(name) { return Int(value) }
        return nil
    }

    func double(_ name: String) -> Double? {
        switch value(name) {
        case let .real(value): value
        case let .integer(value): Double(value)
        default: nil
        }
    }

    func date(_ name: String) -> Date? {
        double(name).map { Date(timeIntervalSince1970: $0) }
    }
}

enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String, sql: String)
    case step(String)

    var description: String {
        switch self {
        case let .open(message): "SQLite open failed: \(message)"
        case let .prepare(message, sql): "SQLite prepare failed: \(message) — SQL: \(sql)"
        case let .step(message): "SQLite step failed: \(message)"
        }
    }
}

/// Thin wrapper over a single SQLite connection. Not thread-safe on its own;
/// concurrency is managed by `Database` (single writer, pooled readers).
final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String, readonly: Bool) throws {
        let flags = readonly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "rc=\(rc)"
            throw SQLiteError.open(message)
        }
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
    }

    func execute(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errmsg)
        defer { sqlite3_free(errmsg) }
        guard rc == SQLITE_OK else {
            throw SQLiteError.step(errmsg.map { String(cString: $0) } ?? errorMessage)
        }
    }

    /// Runs a statement with optional bindings, ignoring any result rows.
    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.step(errorMessage)
        }
    }

    /// Runs a query and returns all result rows.
    func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }

        let columnCount = Int(sqlite3_column_count(statement))
        var indexByName = [String: Int]()
        for index in 0 ..< columnCount {
            indexByName[String(cString: sqlite3_column_name(statement, Int32(index)))] = index
        }

        var rows = [SQLiteRow]()
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw SQLiteError.step(errorMessage) }

            var columns = [SQLiteValue]()
            columns.reserveCapacity(columnCount)
            for index in 0 ..< columnCount {
                columns.append(columnValue(statement, Int32(index)))
            }
            rows.append(SQLiteRow(columns: columns, indexByName: indexByName))
        }
        return rows
    }

    var lastInsertRowId: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    private func prepare(_ sql: String, _ bindings: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw SQLiteError.prepare(errorMessage, sql: sql)
        }
        for (offset, value) in bindings.enumerated() {
            bind(statement, Int32(offset + 1), value)
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: SQLiteValue) {
        switch value {
        case .null:
            sqlite3_bind_null(statement, index)
        case let .integer(value):
            sqlite3_bind_int64(statement, index, value)
        case let .real(value):
            sqlite3_bind_double(statement, index, value)
        case let .text(value):
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case let .blob(value):
            value.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                if let base = buffer.baseAddress, buffer.count > 0 {
                    sqlite3_bind_blob(statement, index, base, Int32(buffer.count), SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_zeroblob(statement, index, 0)
                }
            }
        }
    }

    private func columnValue(_ statement: OpaquePointer?, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(statement, index)))
        case SQLITE_BLOB:
            if let pointer = sqlite3_column_blob(statement, index) {
                let count = Int(sqlite3_column_bytes(statement, index))
                return .blob(Data(bytes: pointer, count: count))
            }
            return .blob(Data())
        default:
            return .null
        }
    }
}
