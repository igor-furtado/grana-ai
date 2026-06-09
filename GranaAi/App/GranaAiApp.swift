import OSLog
import SwiftUI

@main
struct GranaAiApp: App {
    /// Inicializamos o environment uma única vez aqui. Se a inicialização do banco
    /// falhar, registramos o erro e seguimos com um environment "vazio" — mais à frente
    /// (Fase 5) o app exigirá auth e teremos uma tela de erro dedicada.
    @State private var environment: AppEnvironment

    init() {
        let env = AppEnvironment()
        _environment = State(initialValue: env)
        log.database.info("AppEnvironment inicializado com sucesso")

        // Limpeza one-shot: versões anteriores persistiam o tema em
        // `appColorScheme` via `@AppStorage`. O override hoje é por sessão
        // (não persistido), então a chave fica órfã pra quem atualizou.
        // Remoção é idempotente — se não existir, é no-op.
        UserDefaults.standard.removeObject(forKey: "appColorScheme")
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
                        try await Seed.runIfNeeded(container: environment.container)
                    } catch {
                        NoticeCenter.shared.report(error, title: "Falha no seed inicial")
                    }
                    if let setupError = environment.setupError {
                        NoticeCenter.shared.report(setupError, title: "Falha ao iniciar o banco")
                    }
                }
        }
        // Tamanho default na primeira abertura — gabarito do app. Mínimo
        // efetivo vem do `.frame(minWidth:minHeight:)` no `ContentView`;
        // `.windowResizability(.contentSize)` faz o AppKit respeitar isso.
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
    }
}
