import Darwin
import Foundation
import OSLog

/// Shell-out pro binário `codex` em modo não-interativo.
///
/// Usa a autenticação local da assinatura Codex, sem API key ou cobrança
/// variável durante o MVP.
///
/// **Como funciona:**
/// Executa `codex exec --ephemeral` em diretório temporário, com sandbox
/// restrito ao diretório de trabalho + `~/.codex`, raciocínio mínimo e schema
/// de saída.
///
/// **App Sandbox precisa estar OFF** (`ENABLE_APP_SANDBOX = NO` no
/// `project.pbxproj`). Sandbox bloqueia `Process` de executar binários
/// fora do bundle. Decisão consciente: app single-user, local-first; o
/// isolamento adicional não justifica a complexidade de `NSUserUnixTask`.
final class CodexCLIClient: Sendable {
    /// Caminhos onde procuramos o `codex` quando não há configuração explícita.
    private static let defaultSearchPaths: [String] = [
        "~/.local/bin/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "/usr/bin/codex",
    ]

    private let configuredPath: String?
    private let model: String
    private let timeoutSeconds: TimeInterval

    init(
        executablePath: String? = nil,
        model: String,
        // O Codex 0.139.0 pode passar por vários reconnects antes de cair
        // pro caminho HTTP; em testes mínimos isso já consumiu ~118s.
        // 120s vira timeout espúrio mesmo quando a chamada acabaria bem.
        timeoutSeconds: TimeInterval = 300
    ) {
        self.configuredPath = executablePath
        self.model = model
        self.timeoutSeconds = timeoutSeconds
    }

    /// Executa o CLI com um schema fixo de saída. Devolve **o JSON interno
    /// validado pelo schema**, já desempacotado do wrapper do `--output-format json`.
    ///
    /// `userPrompt` vai pelo **stdin** — `--tools` é variádico e gulosamente
    /// consome qualquer arg posicional que venha depois, então passar o prompt
    /// como argumento conflitaria. Stdin também elimina limites de tamanho
    /// de arg do kernel (`ARG_MAX`).
    ///
    /// `systemPrompt` substitui inteiro o system prompt default do harness,
    /// garantindo que o modelo veja só a tarefa de classificação (sem
    /// instruções do repositório, hooks, etc.).
    func runStructured(
        systemPrompt: String,
        userPrompt: String,
        jsonSchema: String
    ) async throws -> Data {
        let executable = try resolveExecutable()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grana-ai-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let schemaURL = temporaryDirectory.appendingPathComponent("schema.json")
        try Data(jsonSchema.utf8).write(to: schemaURL, options: .atomic)

        let args: [String] = [
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            // `codex exec` inicializa estado em `~/.codex/sqlite` e o app usa
            // um diretório temporário fora de qualquer repositório Git.
            // `read-only` quebra a abertura desse state DB; sem
            // `--skip-git-repo-check`, o bootstrap também falha no tmp dir.
            "--skip-git-repo-check",
            "--sandbox", "workspace-write",
            "--add-dir", Self.codexHomeDirectoryPath(),
            "--model", model,
            // `minimal` quebra no Codex 0.139.0 quando o toolset padrão inclui
            // `image_gen`/`web_search`; o backend rejeita a combinação antes
            // mesmo de gerar resposta estruturada.
            "--config", "model_reasoning_effort=\"low\"",
            "--output-schema", schemaURL.path,
        ]

        let prompt = """
        \(systemPrompt)

        \(userPrompt)

        IMPORTANTE:
        - Responda diretamente com o objeto JSON final.
        - Não use ferramentas.
        - Não execute comandos.
        - Não leia arquivos.
        - Não navegue na web.
        """

        return try await runProcess(
            executable: executable,
            arguments: args,
            stdin: prompt,
            currentDirectory: temporaryDirectory
        )
    }

    // MARK: - Process plumbing

    private func runProcess(
        executable: URL,
        arguments: [String],
        stdin: String,
        currentDirectory: URL
    ) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        // GUI apps herdam um PATH minúsculo. Expandimos caminhos comuns e
        // filtramos paths já herdados para evitar duplicatas no ambiente.
        var env = ProcessInfo.processInfo.environment
        let inheritedPath = env["PATH"] ?? ""
        let inheritedComponents = Set(inheritedPath.split(separator: ":").map(String.init))
        let candidates = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]
        let toAppend = candidates.filter { !inheritedComponents.contains($0) }
        if !toAppend.isEmpty {
            let suffix = toAppend.joined(separator: ":")
            env["PATH"] = inheritedPath.isEmpty ? suffix : "\(inheritedPath):\(suffix)"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        let stdinData = Data(stdin.utf8)
        let started = Date()

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await Self.waitForProcess(
                        process: process,
                        stdinPipe: stdinPipe,
                        stdinData: stdinData,
                        stdoutPipe: stdoutPipe,
                        stderrPipe: stderrPipe,
                        started: started
                    )
                }
                group.addTask { [timeoutSeconds] in
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    Self.forceTerminate(process)
                    throw AIError.cliTimeout(seconds: timeoutSeconds)
                }
                guard let first = try await group.next() else {
                    throw AIError.responseParse("Task group finished without result")
                }
                group.cancelAll()
                return first
            }
        } onCancel: {
            Self.forceTerminate(process)
        }
    }

    /// SIGTERM educado, com escalada pra SIGKILL se o processo não morrer em
    /// 2s. Sem o SIGKILL, um CLI travado pré-exit (esperando rede, em loop
    /// de retry, etc.) segura a Task que está dentro do `waitUntilExit`, que
    /// não é cancelável pela Swift Concurrency.
    private static func forceTerminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        // `terminate` é assíncrono — agenda o SIGKILL fora da MainActor.
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    private static func waitForProcess(
        process: Process,
        stdinPipe: Pipe,
        stdinData: Data,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        started: Date
    ) async throws -> Data {
        try process.run()

        // Pipes do macOS têm buffer ~64KB. Mesmo problema vale pros 3 lados:
        // se stdout enche, o processo bloqueia no write antes do exit; se
        // stdin enche, *nosso* write bloqueia antes do CLI ler. Por isso
        // disparamos drains de stdout/stderr E a escrita de stdin em paralelo
        // — todos rodando concorrentes ao `waitUntilExit`. Sem isso, prompts
        // maiores que ~64KB (imports grandes) travam o CLI.
        async let stdoutTask: Data = Self.drain(stdoutPipe.fileHandleForReading)
        async let stderrTask: Data = Self.drain(stderrPipe.fileHandleForReading)
        async let stdinTask: Void = Self.feedStdin(stdinPipe.fileHandleForWriting, data: stdinData)

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }

        await stdinTask
        let stdout = await stdoutTask
        let stderr = await stderrTask
        let elapsed = Date().timeIntervalSince(started)

        log.ai
            .debug(
                "codex CLI exit=\(process.terminationStatus) latency=\(String(format: "%.2f", elapsed))s stdout=\(stdout.count)B stderr=\(stderr.count)B"
            )

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderr, encoding: .utf8) ?? ""
            // Trunca stderr a 2KB pro log/erro não virar muralha.
            let truncated = stderrText.count > 2048
                ? String(stderrText.prefix(2048)) + "…[truncado]"
                : stderrText
            throw AIError.cliExitCode(Int(process.terminationStatus), stderr: truncated)
        }

        return stdout
    }

    /// Lê um `FileHandle` até EOF numa Task detached. Roda concorrente ao
    /// `waitUntilExit` pra evitar bloquear o processo no pipe buffer.
    private static func drain(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .userInitiated) {
            (try? handle.readToEnd()) ?? Data()
        }.value
    }

    /// Escreve o prompt em stdin numa Task detached e fecha o handle pra
    /// sinalizar EOF. Roda concorrente aos drains pra que prompts maiores
    /// que o buffer do pipe (~64KB) não travem antes do CLI consumir.
    /// `try?` engole EPIPE — se o processo já fechou stdin (timeout, erro
    /// precoce), a escrita falha e tudo bem.
    private static func feedStdin(_ handle: FileHandle, data: Data) async {
        await Task.detached(priority: .userInitiated) {
            try? handle.write(contentsOf: data)
            try? handle.close()
        }.value
    }

    // MARK: - Executable resolution

    private static func codexHomeDirectoryPath() -> String {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
            return (configured as NSString).expandingTildeInPath
        }
        return "\(NSHomeDirectory())/.codex"
    }

    private func resolveExecutable() throws -> URL {
        var attempted: [String] = []

        if let configured = configuredPath, !configured.isEmpty {
            let expanded = (configured as NSString).expandingTildeInPath
            attempted.append(expanded)
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        for candidate in Self.defaultSearchPaths {
            let expanded = (candidate as NSString).expandingTildeInPath
            attempted.append(expanded)
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        throw AIError.cliNotFound(searchedPaths: attempted)
    }
}
