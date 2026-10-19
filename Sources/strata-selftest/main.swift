import Foundation

// Minimal test runner: Command Line Tools have no XCTest / Swift Testing macros.
nonisolated(unsafe) var failures: [String] = []
nonisolated(unsafe) var current = ""

func expect(_ ok: @autoclosure () -> Bool, file: StaticString = #fileID, line: UInt = #line) {
    if !ok() { failures.append("\(current) — \(file):\(line)") }
}

struct RequireFailed: Error {}
func require<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value else { failures.append("\(current) — required value was nil at \(file):\(line)"); throw RequireFailed() }
    return value
}
func require(_ ok: Bool, file: StaticString = #fileID, line: UInt = #line) throws {
    if !ok { failures.append("\(current) — requirement failed at \(file):\(line)"); throw RequireFailed() }
}

let checks: [(String, () throws -> Void)] = [
    ("normalizesMessyDesignNames", normalizesMessyDesignNames),
    ("genericNamesNeverFormProjects", genericNamesNeverFormProjects),
    ("similarityNeedsASharedSpecificWord", similarityNeedsASharedSpecificWord),
    ("readsAdobeIdentifiers", readsAdobeIdentifiers),
    ("ignoresPlacedFileIDs", ignoresPlacedFileIDs),
    ("findsPacketInsideBinaryData", findsPacketInsideBinaryData),
    ("rejectsPlaceholderIDs", rejectsPlaceholderIDs),
    ("groupsRenamedRecoveredAndExportedFilesIntoOneProject", groupsRenamedRecoveredAndExportedFilesIntoOneProject),
    ("templatesDoNotMergeUnrelatedClients", templatesDoNotMergeUnrelatedClients),
    ("differentProjectsOfSameClientStaySeparate", differentProjectsOfSameClientStaySeparate),
    ("addsOneGenericWordToSingleWordName", addsOneGenericWordToSingleWordName),
    ("flagsExactDuplicates", flagsExactDuplicates),
    ("scannerReadsRealFilesAndCaches", scannerReadsRealFilesAndCaches),
    ("repeatedNamesInProductFoldersStaySeparate", repeatedNamesInProductFoldersStaySeparate),
    ("printSizesAreOneArtwork", printSizesAreOneArtwork),
    ("saveAsToStartANewJobIsNotTheSameProject", saveAsToStartANewJobIsNotTheSameProject),
]

for (name, run) in checks {
    current = name
    let before = failures.count
    do { try run() } catch is RequireFailed {} catch { failures.append("\(name) — threw \(error)") }
    print(failures.count == before ? "✓ \(name)" : "✗ \(name)")
}
print(failures.isEmpty ? "\nAll \(checks.count) checks passed." : "\n\(failures.count) failure(s):\n" + failures.joined(separator: "\n"))
exit(failures.isEmpty ? 0 : 1)
