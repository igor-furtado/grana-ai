import Foundation

/// Mapeia uma transação OFX para uma das categorias **raiz** do app. É um
/// chute educado pra reduzir o trabalho manual na Fase 3 — a Fase 4 (IA)
/// refina depois. Princípios:
///
/// 1. **Conservador**: na dúvida, manda pra "Não Classificado" em vez de
///    inventar uma categoria duvidosa.
/// 2. **TRNTYPE primeiro, MEMO depois**: o tipo OFX é a fonte mais
///    estruturada; o MEMO entra pra capturar PIX/TED que vêm como
///    PAYMENT/CREDIT genéricos mas semanticamente são transferências.
/// 3. **Sem tabelas em RAM**: recebemos os IDs das raízes resolvidas pelo
///    `ImportStore` e devolvemos um deles — a função fica pura, fácil de testar.
struct OFXCategoryHeuristic {

    /// IDs das categorias raiz relevantes pra heurística. O `ImportStore`
    /// resolve esses IDs uma vez via `CategoryRepository.findRootByName` e
    /// passa pra cada chamada de `categoryId(for:)`.
    struct RootCategoryIDs {
        let unclassified: UUID
        let transfers: UUID?
        let income: UUID?
    }

    let roots: RootCategoryIDs

    func categoryId(for transaction: OFXTransaction) -> UUID {
        // PIX, TED, DOC, TEF — independente do TRNTYPE, são movimentações
        // entre contas. PROJECT.md trata transfer como neutro de saldo.
        if let memo = transaction.memo, memo.containsAny(["pix", "ted ", "doc ", "tef"]) {
            return roots.transfers ?? roots.unclassified
        }
        if let name = transaction.name, name.containsAny(["pix", "ted ", "doc "]) {
            return roots.transfers ?? roots.unclassified
        }

        switch transaction.trnType.uppercased() {
        case "CREDIT", "DEP", "DIRECTDEP", "INT", "DIV":
            return roots.income ?? roots.unclassified
        case "XFER":
            return roots.transfers ?? roots.unclassified
        default:
            // DEBIT/PAYMENT/CHECK/ATM/POS/FEE/SRVCHG/CASH/DIRECTDEBIT/REPEATPMT/OTHER
            return roots.unclassified
        }
    }
}

private extension String {
    /// Busca case-insensitive por qualquer um dos termos. Atalho útil pra
    /// inspeção rápida de MEMO/NAME.
    func containsAny(_ needles: [String]) -> Bool {
        let haystack = self.lowercased()
        for needle in needles {
            if haystack.contains(needle) { return true }
        }
        return false
    }
}
