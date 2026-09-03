import Foundation

// Keeps Docs/methods in step with the code it describes.
//
// It cannot check that the prose is true — nothing can. It checks that the prose is still about
// code that exists, which is the failure mode documentation actually has: a method gets renamed,
// the page keeps its old name, and a reader trusts a description of something that is no longer
// there.
//
// Three checks:
//   1. every symbol named in a page's "Where it lives" table exists in the module it names;
//   2. every Docs/methods page a doc comment points at exists;
//   3. the index lists exactly the pages that are present.
//
// Usage: swift run CheckMethodDocs [package-root]

@MainActor
struct Problem {
    let file: String
    let line: Int
    let message: String
}

let fileManager = FileManager.default
let arguments = CommandLine.arguments
let root = URL(
    fileURLWithPath: arguments.count > 1 ? arguments[1] : fileManager.currentDirectoryPath
)
let methodsURL = root.appendingPathComponent("Docs/methods")
let sourcesURL = root.appendingPathComponent("Sources")

var problems: [Problem] = []

// MARK: Pages

let pageNames = ((try? fileManager.contentsOfDirectory(atPath: methodsURL.path)) ?? [])
    .filter { $0.hasSuffix(".md") && $0 != "README.md" }
    .sorted()

guard !pageNames.isEmpty else {
    FileHandle.standardError.write(Data("no pages under Docs/methods\n".utf8))
    exit(2)
}

/// Contents of a source file, cached: a page names several symbols from one module.
var moduleSources: [String: String] = [:]

@MainActor
func sources(ofModule module: String) -> String? {
    if let cached = moduleSources[module] { return cached }
    let directory = sourcesURL.appendingPathComponent(module)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue,
          let walker = fileManager.enumerator(atPath: directory.path)
    else { return nil }

    var joined = ""
    for case let relative as String in walker where relative.hasSuffix(".swift") {
        let url = directory.appendingPathComponent(relative)
        joined += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    moduleSources[module] = joined
    return joined
}

/// A declaration of `name` in `text`, as a `struct`, `enum`, `protocol`, `func`, `typealias` or
/// `class`. Matching the declaration rather than any mention is what makes the check mean
/// something: a symbol surviving only inside a comment is exactly the case worth catching.
func declares(_ name: String, in text: String) -> Bool {
    let keywords = ["struct", "enum", "protocol", "class", "actor", "typealias", "func"]
    for keyword in keywords where text.contains("\(keyword) \(name)") {
        return true
    }
    return false
}

for pageName in pageNames {
    let pageURL = methodsURL.appendingPathComponent(pageName)
    guard let page = try? String(contentsOf: pageURL, encoding: .utf8) else { continue }
    let lines = page.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    var inTable = false
    var sawTable = false
    for (offset, line) in lines.enumerated() {
        if line.hasPrefix("## ") {
            inTable = line.hasPrefix("## Where it lives")
            if inTable { sawTable = true }
            continue
        }
        guard inTable, line.hasPrefix("|") else { continue }

        // | `Symbol` | `Module` |
        let cells = line.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        }
        guard cells.count >= 2, cells[0] != "Symbol", !cells[0].hasPrefix("---") else { continue }

        // A method's table entry may carry its argument labels; the declaration does not.
        let symbol = String(cells[0].prefix { $0 != "(" })
        let module = cells[1]

        guard let text = sources(ofModule: module) else {
            problems.append(
                Problem(
                    file: "Docs/methods/\(pageName)",
                    line: offset + 1,
                    message: "names module \(module), which has no directory under Sources/"
                )
            )
            continue
        }
        if !declares(symbol, in: text) {
            problems.append(
                Problem(
                    file: "Docs/methods/\(pageName)",
                    line: offset + 1,
                    message: "names \(symbol), which \(module) does not declare"
                )
            )
        }
    }

    if !sawTable {
        problems.append(
            Problem(
                file: "Docs/methods/\(pageName)",
                line: 1,
                message: "has no 'Where it lives' section, so nothing about it can be checked"
            )
        )
    }
}

// MARK: References from code

if let walker = fileManager.enumerator(atPath: sourcesURL.path) {
    for case let relative as String in walker where relative.hasSuffix(".swift") {
        let url = sourcesURL.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard let range = line.range(of: "Docs/methods/") else { continue }
            let tail = line[range.upperBound...]
            let page = String(tail.prefix { $0 != " " && $0 != ")" && $0 != "," && $0 != "#" })
            guard !page.isEmpty else { continue }

            if !fileManager.fileExists(atPath: methodsURL.appendingPathComponent(page).path) {
                problems.append(
                    Problem(
                        file: "Sources/\(relative)",
                        line: offset + 1,
                        message: "points at Docs/methods/\(page), which does not exist"
                    )
                )
            }
        }
    }
}

// MARK: Index

if let index = try? String(
    contentsOf: methodsURL.appendingPathComponent("README.md"),
    encoding: .utf8
) {
    for pageName in pageNames where !index.contains(pageName) {
        problems.append(
            Problem(
                file: "Docs/methods/README.md",
                line: 1,
                message: "does not list \(pageName)"
            )
        )
    }
} else {
    problems.append(Problem(file: "Docs/methods/README.md", line: 1, message: "is missing"))
}

// MARK: Report

for problem in problems.sorted(by: { ($0.file, $0.line) < ($1.file, $1.line) }) {
    print("\(problem.file):\(problem.line): error: \(problem.message)")
}

if problems.isEmpty {
    print("method docs: \(pageNames.count) pages checked, no problems")
    exit(0)
}
exit(1)
