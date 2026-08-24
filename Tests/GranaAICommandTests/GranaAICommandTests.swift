import Dispatch
import Foundation
import Testing
import GranaAICore

@Test func commandReadsJSONFromStdinAndWritesResponseToStdout() throws {
    let result = try runCommand(input: validRequestJSON())

    #expect(result.exitCode == 0)

    let response = try JSONDecoder().decode(ClassificationResponse.self, from: result.stdout)
    #expect(response == ClassificationResponse(
        version: .current,
        results: [
            ClassificationResult(transactionID: "tx-1", outcome: .fallback(reason: .noStrategyAvailable)),
        ]
    ))
}

@Test func commandWritesStructuredErrorForInvalidJSON() throws {
    let result = try runCommand(input: "{")

    #expect(result.exitCode == 1)

    let error = try JSONDecoder().decode(ClassificationContractError.self, from: result.stdout)
    #expect(error == ClassificationContractError(code: .invalidJSON, message: "Invalid JSON payload."))
}

@Test func commandWritesStructuredErrorForUnsupportedVersion() throws {
    try expectCommandError(
        input: validRequestJSON(version: "classification.v0"),
        code: .unsupportedVersion,
        message: "Unsupported contract version: classification.v0"
    )
}

@Test func commandWritesStructuredErrorForMissingTaxonomy() throws {
    try expectCommandError(
        input: """
        {
          "version": "classification.v1",
          "transactions": [
            { "id": "tx-1", "description": "PADARIA CENTRAL" }
          ],
          "context": {
            "locale": "pt-BR"
          }
        }
        """,
        code: .missingTaxonomy,
        message: "Classification request must include taxonomy."
    )
}

@Test func commandWritesStructuredErrorForInvalidTaxonomy() throws {
    try expectCommandError(
        input: """
        {
          "version": "classification.v1",
          "transactions": [
            { "id": "tx-1", "description": "PADARIA CENTRAL" }
          ],
          "taxonomy": {
            "categories": []
          },
          "context": {
            "locale": "pt-BR"
          }
        }
        """,
        code: .invalidTaxonomy,
        message: "Taxonomy must include at least one valid category."
    )
}

@Test func commandWritesStructuredErrorForMalformedPayload() throws {
    try expectCommandError(
        input: """
        {
          "version": "classification.v1",
          "transactions": "not-an-array",
          "taxonomy": {
            "categories": [
              { "id": "alimentacao", "name": "Alimentação" }
            ]
          },
          "context": {
            "locale": "pt-BR"
          }
        }
        """,
        code: .malformedPayload,
        message: "Malformed classification request payload."
    )
}

@Test func commandWritesStructuredErrorForMissingContext() throws {
    try expectCommandError(
        input: """
        {
          "version": "classification.v1",
          "transactions": [
            { "id": "tx-1", "description": "PADARIA CENTRAL" }
          ],
          "taxonomy": {
            "categories": [
              { "id": "alimentacao", "name": "Alimentação" }
            ]
          }
        }
        """,
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
    process.executableURL = packageRoot()
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

private func packageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func validRequestJSON(version: String = "classification.v1") -> String {
    """
    {
      "version": "\(version)",
      "transactions": [
        { "id": "tx-1", "description": "PADARIA CENTRAL" }
      ],
      "taxonomy": {
        "categories": [
          { "id": "alimentacao", "name": "Alimentação" }
        ]
      },
      "context": {
        "locale": "pt-BR"
      }
    }
    """
}
