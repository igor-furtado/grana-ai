import SwiftUI

/// Aliases semânticos sobre os tokens do asset catalog.
///
/// **Tokens base** (auto-gerados pelo Xcode a partir de `Resources/Assets.xcassets/`):
/// `Color.brandPrimary`, `Color.brandSecondary`, `Color.surface`,
/// `Color.surfaceMuted`, `Color.income`, `Color.expense`, `Color.transfer`,
/// `Color.warning`. Cada um tem variante light/dark no `.colorset`.
///
/// **Como adicionar uma cor nova:** crie `<Nome>.colorset/Contents.json` em
/// `Resources/Assets.xcassets/` (com variante dark) — Xcode gera o acessor
/// `Color.<nome>` automaticamente, sem precisar editar este arquivo.
///
/// Os aliases abaixo existem só pra cores que não têm asset próprio
/// (compartilham paleta com outro token mas precisam de nome semântico
/// distinto no callsite). Constrained a `ShapeStyle where Self == Color` pra
/// funcionarem com a sintaxe abreviada `.foregroundStyle(.danger)` —
/// extension em `Color` puro só permitiria `Color.danger` explícito.
extension ShapeStyle where Self == Color {
    /// Sucesso — compartilha paleta com `income` (verde sage).
    static var success: Color { .income }

    /// Erro/destrutivo — compartilha paleta com `expense` (terracotta).
    static var danger: Color { .expense }
}
