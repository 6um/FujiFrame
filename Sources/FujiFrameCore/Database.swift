import Foundation
import SQLite3

final class Database {
    private var handle: OpaquePointer?
    init(_ url: URL, create: Bool = true) throws {
        let flags = SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "打开失败"
            if let handle { sqlite3_close(handle) }; handle = nil
            throw FrameError("无法打开资料库：\(message)")
        }
        do {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = DELETE")
            try execute("PRAGMA synchronous = FULL")
            let version = try query("PRAGMA user_version").first?["user_version"] ?? "0"
            guard version == "0" || version == "1" else { throw FrameError("资料库版本不受支持，请使用更新的 FujiFrame") }
            if version == "0" {
                guard create else { throw FrameError("这不是有效的 FujiFrame 资料库") }
                try transaction {
                    try execute("CREATE TABLE recipes (id TEXT PRIMARY KEY, body TEXT NOT NULL)")
                    try execute("CREATE TABLE versions (id TEXT PRIMARY KEY, recipeID TEXT NOT NULL REFERENCES recipes(id), number INTEGER NOT NULL, body TEXT NOT NULL, UNIQUE(recipeID,number))")
                    try execute("CREATE TABLE photos (id TEXT PRIMARY KEY, body TEXT NOT NULL)")
                    try execute("CREATE TABLE links (id TEXT PRIMARY KEY, photoID TEXT NOT NULL REFERENCES photos(id), versionID TEXT NOT NULL REFERENCES versions(id), body TEXT NOT NULL, UNIQUE(photoID,versionID))")
                    try execute("CREATE TRIGGER immutable_versions BEFORE UPDATE ON versions BEGIN SELECT RAISE(ABORT, 'Versions are immutable'); END")
                    try execute("PRAGMA user_version = 1")
                }
            }
        } catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { if let handle { sqlite3_close(handle) } }
    func query(_ sql: String, _ args: [String] = []) throws -> [[String: String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in args.enumerated() {
            let rc = value.withCString { sqlite3_bind_text(stmt, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard rc == SQLITE_OK else { throw failure() }
        }
        var rows = [[String: String]]()
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw failure() }
            var row = [String: String]()
            for i in 0..<sqlite3_column_count(stmt) {
                if let value = sqlite3_column_text(stmt, i) { row[String(cString: sqlite3_column_name(stmt, i))] = String(cString: value) }
            }
            rows.append(row)
        }
        return rows
    }
    func execute(_ sql: String, _ args: [String] = []) throws { _ = try query(sql, args) }
    func failure() -> FrameError { FrameError("数据库错误：\(String(cString: sqlite3_errmsg(handle)))") }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func all<T: Decodable>(_ table: String, as type: T.Type) throws -> [T] {
        try query("SELECT body FROM \(table)").map { row in
            guard let data = row["body"]?.data(using: .utf8) else { throw FrameError("损坏的资料库记录") }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
    static func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
    func verify() throws {
        guard try query("PRAGMA integrity_check").first?["integrity_check"] == "ok",
              try query("PRAGMA foreign_key_check").isEmpty else { throw FrameError("数据库完整性检查失败") }
    }
}
