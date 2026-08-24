import Dispatch
import Foundation
import Testing
import GranaAICore
import GranaAITestSupport

@Test func commandReadsJSONFromStdinAndWritesResponseToStdout() throws {
    let result = try runCommand(input: FixtureStore.classificationV1String("request-padaria.json"))

    #expect(result.exitCode == 0)

    let response = try JSONDecoder().decode(ClassificationResponse.self, from: result.stdout)
    let expected = try FixtureStore.classificationV1Response("response-padaria.json")
    #expect(response == expected)
}

@Test func commandWritesStructuredErrorForInvalidJSON() throws {
    let result = try runCommand(input: FixtureStore.classificationV1String("error-invalid-json.txt"))

    #expect(result.exitCode == 1)

    let error = try JSONDecoder().decode(ClassificationContractError.self, from: result.stdout)
    #expect(error == ClassificationContractError(code: .invalidJSON, message: "Invalid JSON payload."))
}

@Test func commandWritesStructuredErrorForUnsupportedVersion() throws {
    try expectCommandError(
        input: unsupportedVersionRequestJSON(),
        code: .unsupportedVersion,
        message: "Unsupported contract version: classification.v0"
    )
}

@Test func commandWritesStructuredErrorForMissingTaxonomy() throws {
    try expectCommandError(
        input: FixtureStore.classificationV1String("error-missing-taxonomy.json"),
        code: .missingTaxonomy,
        message: "Classification request must include taxonomy."
    )
}

@Test func commandWritesStructuredErrorForInvalidTaxonomy() throws {
    try expectCommandError(
        input: FixtureStore.classificationV1String("error-invalid-taxonomy.json"),
        code: .invalidTaxonomy,
        message: "Taxonomy must include at least one valid category."
    )
}

@Test func commandWritesStructuredErrorForMalformedPayload() throws {
    try expectCommandError(
        input: FixtureStore.classificationV1String("error-malformed-payload.json"),
        code: .malformedPayload,
        message: "Malformed classification request payload."
    )
}

@Test func commandWritesStructuredErrorForMissingContext() throws {
    try expectCommandError(
        input: FixtureStore.classificationV1String("error-missing-context.json"),
        code: .missingContext,
        message: "Classification request must include context."
    )
}

@Test func commandHarnessCanCancelHungProcess() throws {
    #expect(throws: CommandHarnessError.timedOut) {
        try runCommand(input: "", closeStdin: false, timeout: 0.1)
    }
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: Data
}

private enum CommandHarnessError: Error, Equatable {
    case timedOut
}

private func expectCommandError(
    input: String,
    code: ClassificationContractError.Code,
    message: String
) throws {
    let result = try runCommand(input: input)

    #expect(result.exitCode == 1)

    let error = try JSONDecoder().decode(ClassificationContractError.self, from: result.stdout)
    #expect(error == ClassificationContractError(code: code, message: message))
}

private func runCommand(
    input: String,
    closeStdin: Bool = true,
    timeout: TimeInterval = 2
) throws -> CommandResult {
    let process = Process()
    process.executableURL = FixtureStore.packageRoot()
        .appendingPathComponent(".build")
        .appendingPathComponent("debug")
        .appendingPathComponent("grana-ai")

    let stdin = Pipe()
    let stdout = Pipe()

    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = Pipe()

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
        finished.signal()
    }

    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    if closeStdin {
        try stdin.fileHandleForWriting.close()
    }

    guard finished.wait(timeout: .now() + timeout) == .success else {
        process.terminate()
        try? stdin.fileHandleForWriting.close()
        _ = finished.wait(timeout: .now() + 1)
        throw CommandHarnessError.timedOut
    }

    return CommandResult(
        exitCode: process.terminationStatus,
        stdout: stdout.fileHandleForReading.readDataToEndOfFile()
    )
}

private func unsupportedVersionRequestJSON() throws -> String {
    try FixtureStore.classificationV1String("request-padaria.json")
        .replacingOccurrences(of: "classification.v1", with: "classification.v0")
}
