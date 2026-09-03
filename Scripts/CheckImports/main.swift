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
let sourcesURL = root.appendingPathComponent("Sources")

let rules: Rules
do {
    rules = try JSONDecoder().decode(Rules.self, from: Data(contentsOf: rulesURL))
} catch {
    FileHandle.standardError.write(Data("cannot read \(rulesURL.path): \(error)\n".utf8))
    exit(2)
}

let fileManager = FileManager.default
let targetDirectories: [String]
do {
    targetDirectories = try fileManager.contentsOfDirectory(atPath: sourcesURL.path)
        .filter { name in
            var isDirectory: ObjCBool = false
            let path = sourcesURL.appendingPathComponent(name).path
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        .sorted()
} catch {
    FileHandle.standardError.write(Data("cannot list \(sourcesURL.path): \(error)\n".utf8))
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
    let directory = sourcesURL.appendingPathComponent(target)
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
                    file: "Sources/\(target)/\(relativePath)",
                    line: offset + 1,
                    module: module,
                    target: target
                )
            )
        }
    }
}

for target in unruled {
    print("error: Sources/\(target) has no entry in Scripts/import-rules.json")
}
for violation in violations {
    print("\(violation.file):\(violation.line): error: \(violation.target) may not import \(violation.module)")
}

if violations.isEmpty && unruled.isEmpty {
    print("import rules: \(targetDirectories.count) targets checked, no violations")
    exit(0)
}
exit(1)
