import SwiftUI

/// Aliases semânticos pra estados de UI (sucesso, erro, warning).
///
/// **Tokens base do asset catalog** (auto-gerados pelo Xcode a partir de
/// `Resources/Assets.xcassets/`): `Color.accentColor` (asset `AccentColor` —
/// única cor da marca, drive de tudo interativo/branded), `Color.surface`,
/// `Color.income`, `Color.expense`, `Color.transfer`. Cada um tem variante
/// light/dark no `.colorset`.
///
/// Pra neutros (ícones, strokes, fills sutis, background da sidebar), usa
/// `Color.primary`/`.secondary`/`.tertiary` ou materiais do sistema — eles
/// já flipam com o tema e seguem accessibility settings (Increase Contrast,
/// etc.) sem código custom.
///
/// **Como adicionar uma cor de domínio:** crie `<Nome>.colorset/Contents.json`
/// em `Resources/Assets.xcassets/` (com variante dark) — Xcode gera o acessor
/// `Color.<nome>` automaticamente, sem precisar editar este arquivo.
///
/// **Estados de UI vs cores de domínio.** Os aliases abaixo (`success`,
/// `danger`, `warning`) apontam pras cores **sistêmicas** do macOS
/// (`systemGreen`/`systemRed`/`systemOrange`) — familiares pro usuário
/// (mesmas cores de alerts, toggles, menus do sistema), adaptam light/dark,
/// e respeitam Increase Contrast. Ficam desacopladas das cores de **domínio**
/// (`income`/`expense`/`transfer`) que carregam significado financeiro
/// específico e podem ter tons custom de marca.
///
/// Constrained a `ShapeStyle where Self == Color` pra funcionarem com a
/// sintaxe abreviada `.foregroundStyle(.danger)` em qualquer API que aceite
/// `ShapeStyle`.
extension ShapeStyle where Self == Color {
    /// Sucesso/confirmação. Verde sistema — familiar (toggles ligados,
    /// status badges do macOS).
    static var success: Color {
        Color(.systemGreen)
    }

    /// Erro/destrutivo. Vermelho sistema — familiar (alerts, botões Delete
    /// de menus do macOS, ações destrutivas em sheets).
    static var danger: Color {
        Color(.systemRed)
    }

    /// Atenção não-crítica. Laranja sistema — meio caminho entre `info`
    /// (neutro) e `danger` (erro). Usado pra estados de revisão, valores
    /// suspeitos, duplicatas detectadas.
    static var warning: Color {
        Color(.systemOrange)
    }
}
