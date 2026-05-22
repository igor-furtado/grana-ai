# Grana AI

Aplicação financeira pessoal **macOS** para gerenciar gastos, investimentos e visualizar a saúde financeira através de dashboards e conversa com IA.

**Status:** Fases 0–3 completas ✅ (Fundação, CRUD de transações, Dashboard, Importação CSV/XLSX/OFX). Próxima: Fase 4 — categorização automática com IA.

## Stack

- **UI:** SwiftUI (macOS 26+)
- **Linguagem:** Swift 5.9+
- **Persistência + Sync:** [PowerSync Swift SDK](https://github.com/powersync-ja/powersync-swift) `1.13.1` (SQLite local-first com sync bidirecional)
- **Backend de dados:** Supabase (Postgres) — entra na Fase 5
- **IA:** Anthropic API (HTTP direto) — entra na Fase 4
- **Importação XLSX:** CoreXLSX — entra na Fase 3
- **Charts:** Swift Charts (nativo)

## Como rodar

1. Clone o repositório.
2. Copie o template de configuração:
   ```bash
   cp Config.example.swift GranaAi/Config.swift
   ```
   Pode deixar os placeholders até as fases que usam chaves reais (Anthropic na Fase 4, Supabase/PowerSync na Fase 5).
3. Abra `GranaAi.xcodeproj` no Xcode (15.4+ recomendado).
4. Selecione destination **My Mac** → `cmd+R`.

Primeira build demora alguns minutos porque o PowerSync usa Kotlin Multiplatform internamente e precisa baixar/compilar artefatos. Builds subsequentes são rápidas.

## Documentação

- **[PROJECT.md](./PROJECT.md)** — constituição do projeto: stack, arquitetura, modelo de domínio, convenções.
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — visão técnica das camadas (View → Store → Repository → PowerSync), papel do `AppContainer` e fluxo de dados.
- **[ROADMAP.md](./ROADMAP.md)** — fases de desenvolvimento. Cada fase entrega algo funcional.

## Aviso

Este é um app **single-user**, desenhado pra uso pessoal do desenvolvedor. Sem onboarding genérico, sem multi-tenancy, sem suporte público.
