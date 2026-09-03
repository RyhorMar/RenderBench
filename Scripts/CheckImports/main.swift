import Foundation

// Enforces the layering that the rest of the package only asserts. SwiftPM happily compiles
// `import SwiftUI` inside a target documented as UI-free, so the rule is worth exactly as much
// as the job that checks it.
//
// Usage: swift run CheckImports [package-root]

struct Rules: Decodable {
    struct Target: Decodable {
        let system: [String]
        let local: [String]
    }
    /// Directories to walk, relative to the package root.
    let roots: [String]
    /// Rules keyed by the target's directory, also relative to the package root.
    let targets: [String: Target]
}

struct Violation {
    let file: String
    let line: Int
    let module: String
    let target: String
}

/// Returns the module named by an import declaration, or `nil` when the line is not one.
///
/// Handles the forms that actually occur: leading attributes (`@preconcurrency`,
/// `@_exported`), submodule imports (`import struct Foundation.Data`) and trailing comments.
/// `#if canImport(X)` is deliberately not an import — it asks whether a module exists.
func importedModule(in rawLine: String) -> String? {
    var line = rawLine.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("//") { return nil }

    while line.hasPrefix("@") {
        guard let space = line.firstIndex(of: " ") else { return nil }
        line = String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
    }
    guard line.hasPrefix("import ") else { return nil }

    let declarationKinds: Set<String> = [
        "struct", "class", "enum", "protocol", "func", "var", "let", "typealias", "actor",
    ]
    let tokens = line.dropFirst("import ".count)
        .split(whereSeparator: { $0 == " " || $0 == "\t" })
        .map(String.init)
    guard var module = tokens.first else { return nil }
    if declarationKinds.contains(module), tokens.count > 1 {
        module = tokens[1]
    }
    if let dot = module.firstIndex(of: ".") {
        module = String(module[..<dot])
    }
    return module.isEmpty ? nil : module
}

let arguments = CommandLine.arguments
let root = URL(
    fileURLWithPath: arguments.count > 1 ? arguments[1] : FileManager.default.currentDirectoryPath
)
let rulesURL = root.appendingPathComponent("Scripts/import-rules.json")

let rules: Rules
do {
    rules = try JSONDecoder().decode(Rules.self, from: Data(contentsOf: rulesURL))
} catch {
    FileHandle.standardError.write(Data("cannot read \(rulesURL.path): \(error)\n".utf8))
    exit(2)
}

let fileManager = FileManager.default

/// Directories holding one target's sources, relative to the package root.
///
/// Every root is walked, not just `Sources`. Checking sources alone left the quickstart and every
/// test target exempt from the layering rule — including the one file whose whole purpose is to
/// prove a consumer needs no UI framework.
@MainActor
func discoverTargetDirectories(under roots: [String]) -> [String] {
    var found: [String] = []
    for rootName in roots {
        let rootURL = root.appendingPathComponent(rootName)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else { continue }
        guard isDirectory.boolValue else { continue }

        // A root may itself be one target — `Examples` holds sources directly — or a folder of
        // them, as `Sources` and `Tests` do.
        let entries = (try? fileManager.contentsOfDirectory(atPath: rootURL.path)) ?? []
        let subdirectories = entries.filter { name in
            var isSub: ObjCBool = false
            let path = rootURL.appendingPathComponent(name).path
            return fileManager.fileExists(atPath: path, isDirectory: &isSub) && isSub.boolValue
        }
        let holdsSwiftDirectly = entries.contains { $0.hasSuffix(".swift") }

        if holdsSwiftDirectly { found.append(rootName) }
        // Only directories that actually hold sources need a layering rule. Demanding one for a
        // folder of reference images made the check fail on a directory it has nothing to say
        // about — the rule exists to catch an undeclared target, not an undeclared folder.
        found.append(contentsOf: subdirectories.compactMap { name in
            let path = rootURL.appendingPathComponent(name).path
            guard let walker = fileManager.enumerator(atPath: path) else { return nil }
            for case let entry as String in walker where entry.hasSuffix(".swift") {
                return "\(rootName)/\(name)"
            }
            return nil
        })
    }
    return found.sorted()
}

let targetDirectories = discoverTargetDirectories(under: rules.roots)
guard !targetDirectories.isEmpty else {
    FileHandle.standardError.write(Data("no target directories under \(rules.roots)\n".utf8))
    exit(2)
}

var violations: [Violation] = []
var unruled: [String] = []

for target in targetDirectories {
    guard let rule = rules.targets[target] else {
        unruled.append(target)
        continue
    }
    let allowed = Set(rule.system).union(rule.local)
    let directory = root.appendingPathComponent(target)
    guard let walker = fileManager.enumerator(atPath: directory.path) else { continue }

    for case let relativePath as String in walker where relativePath.hasSuffix(".swift") {
        let fileURL = directory.appendingPathComponent(relativePath)
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

        for (offset, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard let module = importedModule(in: String(line)), !allowed.contains(module) else {
                continue
            }
            violations.append(
                Violation(
                    file: "\(target)/\(relativePath)",
                    line: offset + 1,
                    module: module,
                    target: target
                )
            )
        }
    }
}

for target in unruled {
    print("error: \(target) has no entry in Scripts/import-rules.json")
}
for violation in violations {
    print("\(violation.file):\(violation.line): error: \(violation.target) may not import \(violation.module)")
}

if violations.isEmpty && unruled.isEmpty {
    print("import rules: \(targetDirectories.count) targets checked, no violations")
    exit(0)
}
exit(1)
