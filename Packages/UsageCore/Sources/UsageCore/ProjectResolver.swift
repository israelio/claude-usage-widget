import Foundation

public struct ResolvedProject: Equatable, Sendable {
    /// Project root path (stable key), or "Unknown".
    public var root: String
    /// Last path component of `root` (not yet disambiguated; see `ProjectNaming.displayNames`).
    public var name: String
}

public protocol ProjectResolver: Sendable {
    func resolve(cwd: String?) -> ResolvedProject
}

public enum ProjectNaming {
    public static let unknown = "Unknown"
    public static let home = "Home"

    /// "Home" for the home directory and "/", the last path component otherwise.
    public static func baseName(_ root: String, home homePath: String = NSHomeDirectory()) -> String {
        if root == unknown { return unknown }
        let r = trimmed(root)
        if r == "/" || r == trimmed(homePath) { return home }
        let last = (r as NSString).lastPathComponent
        return last.isEmpty ? r : last
    }

    /// Display name per root. Roots that share a name become `name (parent)`; if the parent name collides too,
    /// the full parent path is used.
    public static func displayNames(for roots: [String], home homePath: String = NSHomeDirectory()) -> [String: String] {
        let unique = Array(Set(roots))
        let base = Dictionary(uniqueKeysWithValues: unique.map { ($0, baseName($0, home: homePath)) })
        let byName = Dictionary(grouping: unique, by: { base[$0]! })
        var out: [String: String] = [:]
        for (name, group) in byName {
            if group.count == 1 { out[group[0]] = name; continue }
            let parents = Dictionary(uniqueKeysWithValues: group.map { ($0, parentPath($0)) })
            let parentNames = parents.mapValues { ($0 as NSString).lastPathComponent.isEmpty ? $0 : ($0 as NSString).lastPathComponent }
            let parentCounts = Dictionary(grouping: group, by: { parentNames[$0]! }).mapValues(\.count)
            for r in group {
                let p = parentCounts[parentNames[r]!]! > 1 ? parents[r]! : parentNames[r]!
                out[r] = "\(name) (\(p))"
            }
        }
        return out
    }

    private static func parentPath(_ root: String) -> String { (trimmed(root) as NSString).deletingLastPathComponent }

    static func trimmed(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

/// Maps a log line's working directory to its project root, merging git worktrees and sub-folders into the main
/// repository. Results are cached per cwd (the filesystem is only consulted once per distinct directory).
public final class DefaultProjectResolver: ProjectResolver, @unchecked Sendable {
    private let home: String
    private let lock = NSLock()
    private var cache: [String: ResolvedProject] = [:]

    public init(home: String = NSHomeDirectory()) { self.home = home }

    public func resolve(cwd: String?) -> ResolvedProject {
        guard let cwd, !cwd.isEmpty else { return ResolvedProject(root: ProjectNaming.unknown, name: ProjectNaming.unknown) }
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[cwd] { return hit }
        let root = Self.root(for: ProjectNaming.trimmed(cwd))
        let r = ResolvedProject(root: root, name: ProjectNaming.baseName(root, home: home))
        cache[cwd] = r
        return r
    }

    private static func root(for path: String) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue, let r = gitRoot(from: path) { return r }
        return heuristicRoot(path)
    }

    /// Walks up looking for `.git`: a directory marks the root; a file (linked worktree) points at the main repository.
    private static func gitRoot(from start: String) -> String? {
        let fm = FileManager.default
        var cur = start
        while true {
            let git = (cur == "/" ? "" : cur) + "/.git"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git, isDirectory: &isDir) {
                return isDir.boolValue ? cur : worktreeRoot(gitFile: git, folder: cur)
            }
            let parent = (cur as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == cur { return nil }
            cur = parent
        }
    }

    /// `gitdir: /repo/.git/worktrees/<name>` -> `/repo`. Anything else (submodules, odd layouts) keeps the folder itself.
    private static func worktreeRoot(gitFile: String, folder: String) -> String {
        guard let text = try? String(contentsOfFile: gitFile, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return folder }
        var dir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !dir.hasPrefix("/") { dir = ((folder + "/" + dir) as NSString).standardizingPath }
        if let r = dir.range(of: "/.git/worktrees/"), r.lowerBound > dir.startIndex { return String(dir[..<r.lowerBound]) }
        return folder
    }

    /// For paths that are gone or not in a repository: strip a worktree segment, else keep the path.
    private static func heuristicRoot(_ path: String) -> String {
        for marker in ["/.claude/worktrees/", "/.worktrees/", "/worktrees/"] {
            if let r = path.range(of: marker, options: .backwards), r.lowerBound > path.startIndex {
                return String(path[..<r.lowerBound])
            }
        }
        return path
    }
}
