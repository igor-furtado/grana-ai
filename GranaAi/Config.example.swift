// COMO USAR:
// 1. Copie este arquivo para `Config.swift` (mesma pasta).
// 2. `Config.swift` está no `.gitignore` — nada do que está aqui vaza pro git.
// 3. Preencha os placeholders conforme as fases:
//      - Fase 4 (IA): `claudeCLIPath` (opcional), `claudeCLIModel`. A
//        categorização usa `claude -p ...` shell-out na assinatura do
//        usuário, então NÃO precisa de API key paga. Garanta que o CLI
//        está instalado e logado: `claude /login`.
//      - Fase 5 (sync): `supabaseURL`, `supabaseAnonKey`, `powerSyncURL`.
//
// Por que `Config.example.swift` versus `.env`:
// Sem dependência extra, type-safe, e o compilador avisa se você usar uma
// chave que não existe.
//
// O bloco abaixo fica em `#if false` pra que Xcode (synchronized folders)
// não compile este arquivo junto com `Config.swift`. Copie o conteúdo
// removendo as guardas.

#if false
    import Foundation

    enum Config {
        static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
        static let supabaseAnonKey = "YOUR_ANON_KEY"
        static let powerSyncURL = "https://YOUR_INSTANCE.powersync.journeyapps.com"

        /// Caminho absoluto pro binário `claude`. nil = auto-detect nos paths comuns.
        static let claudeCLIPath: String? = nil
        static let claudeCLIModel = "claude-haiku-4-5-20251001"
    }
#endif
