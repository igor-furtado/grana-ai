import Foundation

/// Cliente HTTP da categorização assistida online.
///
/// O app fala diretamente com a Edge Function pública do Supabase. A função
/// resolve provider/modelo ativos, aplica pseudonimização e chama o provedor
/// externo. O app continua dono apenas do batch e do recorte de taxonomia.
final class CategorizationAPIClient: Sendable {
    private let urlSession: URLSession
    private let requestTimeout: TimeInterval

    init(
        urlSession: URLSession = .shared,
        requestTimeout: TimeInterval = 900
    ) {
        self.urlSession = urlSession
        self.requestTimeout = requestTimeout
    }

    func categorize(
        _ requestBody: CategorizationPrompt.APIRequest
    ) async throws -> Data {
        guard let endpoint = endpointURL() else {
            throw AIError.invalidConfiguration("Config.supabaseURL")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder.categorization.encode(requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.requestFailed(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Resposta sem HTTPURLResponse")
        }

        guard 200 ..< 300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIError.httpStatus(http.statusCode, body: body)
        }

        return data
    }

    private func endpointURL() -> URL? {
        guard let baseURL = URL(string: Config.supabaseURL) else { return nil }
        return baseURL
            .appendingPathComponent("functions", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("categorize-import", isDirectory: false)
    }
}

private extension JSONEncoder {
    static let categorization: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
