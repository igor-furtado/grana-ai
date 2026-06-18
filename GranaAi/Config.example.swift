// COMO USAR:
// 1. Copie este arquivo para `Config.swift` (mesma pasta).
// 2. `Config.swift` está no `.gitignore` — nada do que está aqui vaza pro git.
// 3. Preencha os placeholders conforme as fases:
//      - Categorização online: `supabaseURL` e `supabaseAnonKey` são usados
//        pela Edge Function pública `/functions/v1/categorize-import`.
//      - Sync: `powerSyncURL`.
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

        static let categorizationTaxonomyVersion = 1
    }
#endif
