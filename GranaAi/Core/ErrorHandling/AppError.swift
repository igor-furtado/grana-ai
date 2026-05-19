import Foundation

/// Protocolo opcional pra erros que querem controlar o **título** exibido no
/// toast global. Sem implementar, o `ErrorCenter` cai num título genérico
/// derivado do tipo do erro ("DatabaseError", "ImportError", …).
///
/// A *mensagem* sempre vem de `LocalizedError.errorDescription`, então os
/// enums de domínio já existentes (`DatabaseError`, `ImportError`, `AIError`,
/// `CategorizationError`) funcionam sem precisar conformar a este protocolo.
protocol UserFacingError: LocalizedError {
    /// Cabeçalho curto do toast. Padrão: nome legível do caso.
    var errorTitle: String { get }
}

/// Tupla `(título, mensagem)` que o `ErrorCenter` consome.
struct AppErrorPresentation: Equatable {
    let title: String
    let message: String

    /// Extrai título + descrição de qualquer `Error`. A heurística cobre os
    /// erros tipados do app (todos `LocalizedError` em PT-BR) e degrada
    /// gracioso pra `NSError`/`Error` cru.
    static func from(_ error: Error, overrideTitle: String? = nil) -> AppErrorPresentation {
        let message: String
        if let localized = error as? LocalizedError, let desc = localized.errorDescription {
            message = desc
        } else {
            message = (error as NSError).localizedDescription
        }

        let title: String = {
            if let overrideTitle { return overrideTitle }
            if let userFacing = error as? UserFacingError { return userFacing.errorTitle }
            return defaultTitle(for: error)
        }()

        return AppErrorPresentation(title: title, message: message)
    }

    /// Título "amigável" derivado do tipo. Mapeia os enums conhecidos pra
    /// rótulos em PT-BR; tipos desconhecidos viram "Erro inesperado".
    private static func defaultTitle(for error: Error) -> String {
        switch error {
        case is DatabaseError:        return "Erro no banco"
        case is ImportError:          return "Erro na importação"
        case is AIError:              return "Erro na IA"
        case is CategorizationError:  return "Erro na categorização"
        default:                      return "Erro inesperado"
        }
    }
}
