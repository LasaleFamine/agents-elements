import Foundation

/// Byte-level scanning helpers for the JSONL transcript corpus.
///
/// The corpus runs to hundreds of megabytes spread over a few thousand very long lines.
/// Swift `String` search at that size is the whole cost of a scan — `range(of:)` bridges
/// to NSString, and `split`/`contains` walk graphemes — so everything here works on raw
/// UTF-8 bytes and only the handful of lines that actually carry data we surface are ever
/// turned into JSON.
enum Bytes {
    typealias Buf = UnsafeRawBufferPointer

    static let newline: UInt8 = 0x0A
    static let quote: UInt8 = 0x22
    static let backslash: UInt8 = 0x5C
    static let openBrace: UInt8 = 0x7B
    static let closeBrace: UInt8 = 0x7D

    /// UTF-8 bytes of a literal, to be held in a `static let` and reused as a needle.
    static func pattern(_ s: String) -> [UInt8] { Array(s.utf8) }

    @inline(__always)
    static func slice(_ buf: Buf, _ range: Range<Int>) -> Buf {
        UnsafeRawBufferPointer(rebasing: buf[range])
    }

    /// Byte ranges of every non-empty newline-delimited line.
    static func lineRanges(_ buf: Buf) -> [Range<Int>] {
        guard let base = buf.baseAddress else { return [] }
        var out: [Range<Int>] = []
        var start = 0
        while start < buf.count {
            guard let hit = memchr(base + start, Int32(newline), buf.count - start) else {
                out.append(start..<buf.count)
                break
            }
            let idx = UnsafeRawPointer(hit) - base
            if idx > start { out.append(start..<idx) }
            start = idx + 1
        }
        return out
    }

    /// Offset of `needle` within `buf`, or nil.
    static func find(_ buf: Buf, _ needle: [UInt8], from: Int = 0) -> Int? {
        guard let base = buf.baseAddress, !needle.isEmpty,
              from >= 0, buf.count - from >= needle.count else { return nil }
        let hit = needle.withUnsafeBytes { n in
            memmem(base + from, buf.count - from, n.baseAddress!, n.count)
        }
        guard let hit else { return nil }
        return UnsafeRawPointer(hit) - base
    }

    static func contains(_ buf: Buf, _ needle: [UInt8]) -> Bool { find(buf, needle) != nil }

    /// The string value that follows `needle` (which must end in the opening quote,
    /// e.g. `"model":"`). Escapes terminate correctly and are unescaped via JSON on the
    /// rare line that has any.
    static func quoted(_ buf: Buf, after needle: [UInt8], from: Int = 0) -> String? {
        guard let hit = find(buf, needle, from: from) else { return nil }
        var i = hit + needle.count
        var escaped = false
        while i < buf.count {
            let b = buf[i]
            if b == backslash { escaped = true; i += 2; continue }
            if b == quote { break }
            i += 1
        }
        guard i <= buf.count else { return nil }
        let raw = slice(buf, (hit + needle.count)..<min(i, buf.count))
        guard escaped else { return String(decoding: raw, as: UTF8.self) }
        var json = Data([quote]); json.append(contentsOf: raw); json.append(quote)
        return (try? JSONDecoder().decode(String.self, from: json))
            ?? String(decoding: raw, as: UTF8.self)
    }

    /// The balanced `{…}` object that starts at the first `{` after `needle`. Braces
    /// inside JSON strings are skipped, so this survives braces in message content.
    static func object(_ buf: Buf, after needle: [UInt8], from: Int = 0) -> Buf? {
        guard let hit = find(buf, needle, from: from) else { return nil }
        var i = hit + needle.count
        while i < buf.count, buf[i] != openBrace {
            // Anything other than whitespace between the key and `{` means this key
            // isn't an object — give up rather than grabbing an unrelated one.
            if buf[i] != 0x20 && buf[i] != 0x09 { return nil }
            i += 1
        }
        guard i < buf.count else { return nil }
        let start = i
        var depth = 0
        var inString = false
        while i < buf.count {
            let b = buf[i]
            if inString {
                if b == backslash { i += 2; continue }
                if b == quote { inString = false }
            } else if b == quote {
                inString = true
            } else if b == openBrace {
                depth += 1
            } else if b == closeBrace {
                depth -= 1
                if depth == 0 { return slice(buf, start..<(i + 1)) }
            }
            i += 1
        }
        return nil
    }

    /// JSON object parsed out of a byte slice (JSONSerialization — markedly faster than
    /// Codable, and we only ever want a few keys).
    static func json(_ buf: Buf) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(buf)) as? [String: Any]
    }
}

/// Collects results from `DispatchQueue.concurrentPerform` workers. Per-file parsing is
/// hundreds of milliseconds, so a plain lock costs nothing next to it.
final class Collector<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    init(reserving capacity: Int = 0) { items.reserveCapacity(capacity) }

    func add(_ item: T) {
        lock.lock(); items.append(item); lock.unlock()
    }

    var all: [T] {
        lock.lock(); defer { lock.unlock() }; return items
    }
}

extension FS {
    static func readData(_ url: URL) -> Data? {
        // Mapped: parsing runs in parallel, so buffering whole files would peak at the
        // sum of the largest N transcripts. Safe here because both agents only ever
        // append to a transcript — a mapped file that got truncated under us would fault.
        (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? (try? Data(contentsOf: url))
    }
}

/// Runs `body` for every index in parallel across the machine's cores.
func parallelFor(_ count: Int, _ body: @Sendable (Int) -> Void) {
    guard count > 1 else {
        if count == 1 { body(0) }
        return
    }
    DispatchQueue.concurrentPerform(iterations: count, execute: body)
}
