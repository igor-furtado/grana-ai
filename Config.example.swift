import Foundation

// COMO USAR:
// 1. Copie este arquivo para `Config.swift` (mesma pasta).
// 2. `Config.swift` está no `.gitignore` — chaves reais NÃO vão pro git.
// 3. Nesta Fase 0 pode deixar os placeholders abaixo: o app não conecta
//    em nenhum backend ainda. As chaves passam a ser usadas em:
//      - Fase 4: `anthropicAPIKey`
//      - Fase 5: `supabaseURL`, `supabaseAnonKey`, `powerSyncURL`
//
// Por que `Config.example.swift` versus `.env`:
// Sem dependência extra, type-safe, e o compilador avisa se você usar uma
// chave que não existe.

enum Config {
    static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    static let supabaseAnonKey = "YOUR_ANON_KEY"
    static let powerSyncURL = "https://YOUR_INSTANCE.powersync.journeyapps.com"
    static let anthropicAPIKey = "YOUR_ANTHROPIC_KEY"
}
