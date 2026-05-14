import OSLog
import SwiftUI

@main
struct GranaAiApp: App {
    // Inicializamos o environment uma única vez aqui. Se a inicialização do banco
    // falhar, registramos o erro e seguimos com um environment "vazio" — mais à frente
    // (Fase 5) o app exigirá auth e teremos uma tela de erro dedicada.
    @State private var environment: AppEnvironment

    init() {
        let env = AppEnvironment()
        _environment = State(initialValue: env)
        log.database.info("AppEnvironment inicializado com sucesso")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
                .task {
                    // Seed roda toda execução, mas é idempotente (checa se as
                    // tabelas estão vazias antes de inserir). `.task` cancela
                    // automaticamente se a janela sumir antes de terminar.
                    do {
                        try await Seed.runIfNeeded(database: environment.database)
                    } catch {
                        log.database.error("Seed falhou: \(String(describing: error))")
                    }
                }
        }
    }
}
