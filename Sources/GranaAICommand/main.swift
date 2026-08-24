import Darwin
import Foundation
import GranaAICore

@main
struct GranaAICommand {
    static func main() {
        let codec = ClassificationJSONCodec()
        let memory = LocalClassificationMemory.configured()
        let input = FileHandle.standardInput.readDataToEndOfFile()

        do {
            switch Array(CommandLine.arguments.dropFirst()) {
            case []:
                let service = ClassificationService(memory: memory)
                let request = try codec.decodeRequest(from: input)
                let response = try service.classify(request)
                let output = try codec.encodeResponse(response)
                writeJSON(output, to: .standardOutput)
            case ["learn"]:
                let request = try codec.decodeLearningRequest(from: input)
                try memory.learn(request)
            default:
                throw ClassificationContractError(
                    code: .invalidCommand,
                    message: "Unsupported command."
                )
            }
        } catch let error as ClassificationContractError {
            writeContractError(error, using: codec)
            exit(1)
        } catch {
            writeContractError(
                ClassificationContractError(
                    code: .internalError,
                    message: "Internal classification error."
                ),
                using: codec
            )
            exit(1)
        }
    }

    private static func writeContractError(
        _ error: ClassificationContractError,
        using codec: ClassificationJSONCodec
    ) {
        let output = (try? codec.encodeError(error)) ?? Data()
        writeJSON(output, to: .standardOutput)
    }

    private static func writeJSON(_ data: Data, to fileHandle: FileHandle) {
        fileHandle.write(data)
        fileHandle.write(Data("\n".utf8))
    }
}
