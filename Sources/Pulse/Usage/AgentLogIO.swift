import Foundation

/// Read-only helpers for the files an agent leaves behind.
///
/// Every reader that parses a transcript, a capture or a dropped log needs the
/// same handful of things: walk a set of known roots without walking the whole
/// home, tolerate a half-written line, and only ever turn an actually-decoded
/// value into a number. This is that handful, so a new client does not
/// reimplement it — and, more to the point, so two readers cannot disagree
/// about what "malformed" or "missing" means.
///
/// **Nothing here invents a value.** A missing key is nil, not zero; a broken
/// line is skipped, not repaired; a timestamp is never guessed from a file's
/// modification date or the clock. A caller that cannot read its store says so
/// rather than showing a figure nobody measured.
enum AgentLogIO {
    // MARK: - Files

    /// Every regular file under `roots` that matches the filters.
    ///
    /// `roots` may name directories or files; callers pass the **specific,
    /// known** places their agent writes rather than a broad tree. A directory
    /// is walked recursively, hidden files and hidden subdirectories included,
    /// so a dot-directory store is not silently empty. SQLite's `-shm`
    /// sidecar is excluded everywhere: it is shared memory a read touches.
    ///
    /// With both `extensions` and `names` empty every regular file matches.
    /// When either is non-empty a file matches if it satisfies **either**
    /// filter, so `extensions: ["jsonl"], names: ["state.json"]` takes both.
    ///
    /// Roots and results are normalized and symlink-resolved for ordering and
    /// de-duplication, so a path reachable two ways is one file.
    static func files(
        in roots: [URL],
        extensions: Set<String> = [],
        names: Set<String> = []
    ) -> [URL] {
        let manager = FileManager.default
        let wantsExtension = !extensions.isEmpty
        let wantsName = !names.isEmpty

        var seenRoots: Set<String> = []
        let ordered = roots
            .map { $0.standardizedFileURL }
            .sorted { $0.path < $1.path }
            .filter { seenRoots.insert($0.path).inserted }

        let keys: [URLResourceKey] = [.isRegularFileKey]
        var candidates: [URL] = []

        for root in ordered {
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                guard let walker = manager.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsPackageDescendants]
                ) else { continue }

                for case let file as URL in walker {
                    guard matches(
                        file, extensions: extensions, names: names,
                        wantsExtension: wantsExtension, wantsName: wantsName
                    ) else { continue }
                    guard
                        let values = try? file.resourceValues(forKeys: Set(keys)),
                        values.isRegularFile == true
                    else { continue }
                    candidates.append(file.standardizedFileURL)
                }
            } else {
                guard matches(
                    root, extensions: extensions, names: names,
                    wantsExtension: wantsExtension, wantsName: wantsName
                ) else { continue }
                guard
                    let values = try? root.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true
                else { continue }
                candidates.append(root)
            }
        }

        var resolved: [(canonical: String, url: URL)] = candidates.map { file in
            (canonical: file.resolvingSymlinksInPath().path, url: file)
        }
        resolved.sort { lhs, rhs in
            if lhs.canonical == rhs.canonical { return lhs.url.path < rhs.url.path }
            return lhs.canonical < rhs.canonical
        }
        var seen: Set<String> = []
        var files: [URL] = []
        for file in resolved where seen.insert(file.canonical).inserted {
            files.append(file.url)
        }
        return files
    }

    private static func matches(
        _ url: URL,
        extensions: Set<String>,
        names: Set<String>,
        wantsExtension: Bool,
        wantsName: Bool
    ) -> Bool {
        if url.lastPathComponent.hasSuffix("-shm") { return false }
        if !wantsExtension, !wantsName { return true }
        if wantsExtension, extensions.contains(url.pathExtension) { return true }
        if wantsName, names.contains(url.lastPathComponent) { return true }
        return false
    }

    // MARK: - JSON

    /// Parses a whole file as JSON. Malformed content or unreadable bytes are
    /// nil, never a partial value.
    static func json(at url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Parses a JSONL file into objects, skipping any line that is not one.
    ///
    /// A log being appended to can end mid-line, and one corrupt row must not
    /// cost the rest. Non-object JSON (an array, a bare number) is skipped for
    /// the same reason the caller wants objects.
    static func jsonLines(at url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }

        var rows: [[String: Any]] = []
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard
                let value = try? JSONSerialization.jsonObject(with: Data(line)),
                let object = value as? [String: Any]
            else { continue }
            rows.append(object)
        }
        return rows
    }

    /// A JSON object, or nil for anything that is not one.
    static func object(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    /// A non-blank string, trimmed. Whitespace-only is nil rather than a name.
    static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Numbers

    /// A token count, or nil.
    ///
    /// Only a finite, non-negative whole number that fits an `Int` is a count.
    /// A decimal, an overflowed value, a boolean and a missing key all come
    /// back nil — **and nil is not zero**: a figure that was never written is
    /// not a figure of nothing. Nothing here traps on a hostile value.
    static func count(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return int(from: number) }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Int(trimmed), parsed >= 0 else { return nil }
            return parsed
        }
        return nil
    }

    /// A whole number's `Int`, or nil for a boolean, a fraction or an overflow.
    ///
    /// `NSNumber.objCType` is what keeps this from trapping: `c` is how a
    /// boolean is stored and is refused outright, an integer type is read
    /// through its exact `Int64`/`UInt64`, and a floating type is accepted only
    /// when `Int(exactly:)` says it is a whole number in range.
    private static func int(from number: NSNumber) -> Int? {
        switch UInt8(bitPattern: number.objCType.pointee) {
        case UInt8(ascii: "c"):
            return nil
        case UInt8(ascii: "i"), UInt8(ascii: "s"), UInt8(ascii: "l"), UInt8(ascii: "q"):
            let value = number.int64Value
            guard value >= 0, let result = Int(exactly: value) else { return nil }
            return result
        case UInt8(ascii: "C"), UInt8(ascii: "I"), UInt8(ascii: "S"),
             UInt8(ascii: "L"), UInt8(ascii: "Q"):
            guard let result = Int(exactly: number.uint64Value) else { return nil }
            return result
        case UInt8(ascii: "f"), UInt8(ascii: "d"):
            let value = number.doubleValue
            guard value.isFinite, value >= 0, let result = Int(exactly: value) else { return nil }
            return result
        default:
            return nil
        }
    }

    // MARK: - Time

    /// A timestamp, or nil.
    ///
    /// An ISO 8601 string is read with or without fractional seconds and with
    /// or without a timezone offset. A number — or a string that is exactly a
    /// number — is read in the unit the caller states: **seconds by default,
    /// milliseconds only when asked**, never guessed from the magnitude. A
    /// non-finite number and a value a `Date` cannot hold are both nil. The
    /// clock and a file's modification date are never used to fill a gap.
    static func timestamp(_ value: Any?, milliseconds: Bool = false) -> Date? {
        guard let value else { return nil }

        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let date = Self.iso(trimmed) { return date }
            guard let number = Double(trimmed) else { return nil }
            return date(from: number, milliseconds: milliseconds)
        }

        if let number = value as? NSNumber {
            // A boolean is not a timestamp; `c` is how it is stored.
            guard UInt8(bitPattern: number.objCType.pointee) != UInt8(ascii: "c") else { return nil }
            return date(from: number.doubleValue, milliseconds: milliseconds)
        }

        return nil
    }

    private static func date(from number: Double, milliseconds: Bool) -> Date? {
        guard number.isFinite else { return nil }
        let seconds = milliseconds ? number / 1000 : number
        guard seconds.isFinite else { return nil }
        let date = Date(timeIntervalSince1970: seconds)
        guard date.timeIntervalSince1970.isFinite else { return nil }
        return date
    }

    /// Parses an ISO 8601 string with a stated offset, fractional seconds or
    /// neither. **Built per call**: `ISO8601DateFormatter` is not `Sendable`,
    /// and this type is reached from many readers at once.
    private static func iso(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
