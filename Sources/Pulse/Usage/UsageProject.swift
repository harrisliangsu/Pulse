// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Project identity survives reading and caching; its short name is only a label.
struct UsageProject: Hashable, Codable, Sendable {
    enum Identity: Hashable, Codable, Sendable {
        case directory(String)
        case label(String)
        /// A store's project folder when the working directory is not known.
        case source(String)
    }

    let identity: Identity
    let name: String

    init?(_ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if value.hasPrefix("/") {
            // A folder a tool made for a chat that has no project is not one.
            guard !Self.isScratchDirectory(value) else { return nil }
            // Normalize separators only. Resolving symlinks or `..` would make
            // historical attribution depend on the current filesystem.
            let path = Self.repository(of: "/" + value.split(separator: "/").joined(separator: "/"))
            identity = .directory(path)
            name = path.split(separator: "/").last.map(String.init) ?? "/"
        } else {
            identity = .label(value)
            // A workspace URI that is not a local path — VS Code's Remote-SSH
            // `vscode-remote://ssh-remote%2Bhost/home/me/proj` — is still one
            // project, named by its last folder; the whole URI stays its
            // identity, so the same folder on two hosts is not merged.
            if value.contains("://"), let url = URL(string: value),
               !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" {
                name = url.lastPathComponent
            } else {
                name = value
            }
        }
    }

    init(source: String, name: String) {
        identity = .source(source)
        self.name = name
    }

    var path: String? {
        if case .directory(let path) = identity { return path }
        return nil
    }

    /// **A worktree an agent works in is its repository's work.** Claude
    /// Code puts each one at `<repo>/.claude/worktrees/<name>`, and named by
    /// its last folder every subagent's run was a project of its own
    /// ("agent-a4734cf…") beside the repository it was done for. A string
    /// rule, like the rest of this type: nothing on disk is consulted.
    static func repository(of path: String) -> String {
        guard let range = path.range(of: "/.claude/worktrees/"), range.lowerBound > path.startIndex else { return path }
        return String(path[..<range.lowerBound])
    }

    /// **A scratch folder a tool makes is no project.** Codex Desktop opens
    /// a chat that has none in `~/Documents/Codex/<yyyy-mm-dd>/<slug of the
    /// first prompt>`, and DeepSeek Harness falls back to
    /// `…/deepseek-harness/default-workspace`; read as projects, each chat
    /// became one of its own (and the slug is the prompt's own words). Such a
    /// directory reads as the session having none, the same as a transcript
    /// that states no directory. A string rule, like the rest of this type:
    /// nothing on disk is consulted. A folder under one is scratch too — a
    /// tool started inside it still has no project.
    static func isScratchDirectory(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        for index in parts.indices {
            if index + 1 < parts.count, parts[index] == "deepseek-harness", parts[index + 1] == "default-workspace" {
                return true
            }
            // The slug is the last of the four, so it must be there.
            if index + 3 < parts.count, parts[index] == "Documents", parts[index + 1] == "Codex",
               isDate(parts[index + 2]) {
                return true
            }
        }
        return false
    }

    /// `yyyy-mm-dd`, as Codex Desktop names a day's folder.
    private static func isDate(_ part: Substring) -> Bool {
        let bytes = Array(part.utf8)
        guard bytes.count == 10 else { return false }
        return bytes.enumerated().allSatisfy { index, byte in
            index == 4 || index == 7 ? byte == UInt8(ascii: "-") : (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        }
    }

    /// A project read from a cache, or nil when it names a scratch folder:
    /// ledgers kept before `isScratchDirectory` existed hold them as
    /// projects, and are corrected as they are read rather than waiting for
    /// a rescan the store may never need.
    var unlessScratch: UsageProject? {
        if let path, Self.isScratchDirectory(path) { return nil }
        return self
    }

    private enum CodingKeys: String, CodingKey { case identity, name }

    /// Ledgers cached before `repository(of:)` existed hold worktree paths;
    /// they are folded in as they are read rather than waiting for a rescan.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try container.decode(Identity.self, forKey: .identity)
        let name = try container.decode(String.self, forKey: .name)
        if case .directory(let path) = identity, Self.repository(of: path) != path {
            let repository = Self.repository(of: path)
            self.identity = .directory(repository)
            self.name = repository.split(separator: "/").last.map(String.init) ?? "/"
        } else {
            self.identity = identity
            self.name = name
        }
    }

    /// Extend only ambiguous directory names, using the shortest distinct suffix.
    static func displayNames(for projects: Set<UsageProject>) -> [UsageProject: String] {
        let groups = Dictionary(grouping: projects, by: \.name)
        var names: [UsageProject: String] = [:]
        for group in groups.values {
            guard !Task.isCancelled else { return [:] }
            let peers = Set(group)
            for project in group {
                names[project] = displayName(for: project, among: peers)
            }
        }
        return names
    }

    static func displayName(for project: UsageProject, among projects: Set<UsageProject>) -> String {
        let peers = projects.filter { $0 != project && $0.name == project.name }
        guard !peers.isEmpty else { return project.name }
        guard let path = project.path else {
            if case .source(let source) = project.identity {
                return source
            }
            return project.name
        }
        let parts = path.split(separator: "/")
        for count in 2...max(2, parts.count) {
            let suffix = parts.suffix(count).joined(separator: "/")
            if peers.allSatisfy({ peer in
                guard let other = peer.path else { return suffix != peer.name }
                return other.split(separator: "/").suffix(count).joined(separator: "/") != suffix
            }) { return suffix }
        }
        return path
    }
}
