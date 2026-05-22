import Darwin
import Foundation
import OSLog

/// Shell-out pro binário `claude` (Claude Code CLI) em modo não-interativo.
///
/// **Por que CLI e não API HTTP:** a assinatura Claude (Pro/Max) cobre uso via
/// CLI/Desktop com auth OAuth da conta — não cobre `api.anthropic.com`, que
/// é faturado à parte. Pra um app pessoal cujo objetivo é economizar dinheiro,
/// shell-out aproveita a assinatura sem custo adicional por categorização.
///
/// **Como funciona:**
/// 1. Spawna `claude -p --output-format json --json-schema ... --system-prompt ...`.
/// 2. CLI usa o token OAuth do usuário (lido do keychain) e devolve um wrapper
///    `{"type":"result","result":"<inner JSON>"}` no stdout.
/// 3. Cliente extrai o `result`, decodifica o JSON interno e devolve raw `Data`.
/// 4. Caller (`CategorizationPrompt.parseResults`) decodifica a estrutura final.
///
/// **App Sandbox precisa estar OFF** (`ENABLE_APP_SANDBOX = NO` no
/// `project.pbxproj`). Sandbox bloqueia `Process` de executar binários
/// fora do bundle. Decisão consciente: app single-user, local-first; o
/// isolamento adicional não justifica a complexidade de `NSUserUnixTask`.
final class ClaudeCLIClient: Sendable {
    /// Caminhos onde a gente procura o `claude` se `Config.claudeCLIPath` for
    /// nil. Ordem importa — `~/.local/bin` é o default do instalador oficial.
    private static let defaultSearchPaths: [String] = [
        "~/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude",
    ]

    private let configuredPath: String?
    private let model: String
    private let timeoutSeconds: TimeInterval

    init(
        executablePath: String? = nil,
        model: String,
        timeoutSeconds: TimeInterval = 120
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
    /// CLAUDE.md, hooks, etc.).
    func runStructured(
        systemPrompt: String,
        userPrompt: String,
        jsonSchema: String
    ) async throws -> Data {
        let executable = try resolveExecutable()

        // `--tools ""` zera o toolset — o classificador não precisa de Bash/Edit/etc.
        // `--no-session-persistence` evita poluir o histórico do CLI do usuário.
        // `--disable-slash-commands` evita que substrings tipo `/foo` no
        // user prompt sejam interpretadas como skills.
        let args: [String] = [
            "-p",
            "--no-session-persistence",
            "--disable-slash-commands",
            "--output-format", "json",
            "--json-schema", jsonSchema,
            "--system-prompt", systemPrompt,
            "--model", model,
            "--tools", "",
        ]

        let result = try await runProcess(
            executable: executable,
            arguments: args,
            stdin: userPrompt
        )
        return try unwrapResultField(rawStdout: result)
    }

    // MARK: - Process plumbing

    private func runProcess(
        executable: URL,
        arguments: [String],
        stdin: String
    ) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        // GUI apps herdam um PATH minúsculo. O `claude` v2.1 pode invocar
        // `node`/`bun` internamente — expandir PATH cobre o caso. Filtramos
        // paths que já estão no PATH herdado pra evitar duplicatas (que poluem
        // o env em diagnósticos sem trazer benefício).
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

        log.ai.debug("claude CLI exit=\(process.terminationStatus) latency=\(String(format: "%.2f", elapsed))s stdout=\(stdout.count)B stderr=\(stderr.count)B")

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

    // MARK: - Output parsing

    /// `--output-format json` devolve um wrapper. Quando `--json-schema` é
    /// usado, o JSON validado vem em `structured_output` (já como objeto JSON,
    /// não string). Sem schema, o texto livre do modelo vem em `result`.
    ///
    /// Estratégia: prefere `structured_output` (caminho rápido + tipado);
    /// cai pra `result` quando o schema não foi aplicado.
    private func unwrapResultField(rawStdout: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: rawStdout) as? [String: Any] else {
            throw AIError.responseParse("stdout não é objeto JSON: \(String(data: rawStdout, encoding: .utf8)?.prefix(200) ?? "")")
        }

        if let isError = object["is_error"] as? Bool, isError {
            let result = (object["result"] as? String) ?? "(sem detalhe)"
            throw AIError.responseParse("Claude CLI reportou is_error=true: \(result.prefix(500))")
        }

        // Caminho preferido: `structured_output` quando o CLI aplica o
        // `--json-schema`. Vem como objeto JSON aninhado — re-serializa
        // pra Data antes de devolver.
        if let structured = object["structured_output"] as? [String: Any] {
            return try JSONSerialization.data(withJSONObject: structured, options: [])
        }

        // Fallback: campo `result` como string (modo sem schema, ou versão
        // antiga do CLI).
        if let inner = object["result"] as? String, !inner.isEmpty,
           let data = inner.data(using: .utf8) {
            return data
        }

        // Nem `structured_output` nem `result` utilizáveis — dumpa pro log
        // pra diagnóstico e lança.
        let dump = String(data: rawStdout, encoding: .utf8)?.prefix(1500) ?? "<não-UTF8>"
        log.ai.error("claude CLI sem output utilizável. Wrapper: \(String(dump), privacy: .public)")
        throw AIError.responseParse("Nem 'structured_output' nem 'result' utilizáveis")
    }

    // MARK: - Executable resolution

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
