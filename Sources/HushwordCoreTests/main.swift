import Darwin

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expectEqual(_ actual: String, _ expected: String, _ name: String) throws {
    guard actual == expected else {
        throw TestFailure(description: "\(name)\nexpected: \(expected.debugDescription)\nactual:   \(actual.debugDescription)")
    }
}

let tests: [(String, () throws -> Void)] =
    transcriptCleanerTests
    + aiPolishTests
    + finalTranscriptPolicyTests
    + aiCommandTests
    + interactionPolicyTests
    + recognitionSettingsTests
    + dictationContextTests
    + whisperPolicyTests

var failures = 0
for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(error)")
    }
}

guard failures == 0 else {
    exit(1)
}
