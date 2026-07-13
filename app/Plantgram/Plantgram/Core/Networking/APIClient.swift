import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case message(String)
    case server(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The API URL is invalid."
        case .invalidResponse:
            "The server returned an invalid response."
        case .message(let message):
            message
        case .server(let message):
            message
        case .unauthorized:
            "Your session has expired. Please sign in again."
        }
    }
}

final class APIClient {
    var baseURL: URL
    var urlSession: URLSession
    var onUnauthorized: (() async -> String?)?

    static let live = APIClient(
//        baseURL: URL(string: "http://localhost:8080")!,
        baseURL: URL(string: "https://plantgram.janssen.tech")!,
        urlSession: .shared
    )

    init(baseURL: URL, urlSession: URLSession) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func get<Response: Decodable>(_ path: String, accessToken: String? = nil) async throws -> Response {
        var request = try makeRequest(path: path, method: "GET", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, accessToken: String? = nil) async throws -> Response {
        var request = try makeRequest(path: path, method: "POST", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body, accessToken: String? = nil) async throws -> Response {
        var request = try makeRequest(path: path, method: "PATCH", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    func delete(_ path: String, accessToken: String? = nil) async throws {
        let request = try makeRequest(path: path, method: "DELETE", accessToken: accessToken)
        try await sendWithoutBody(request)
    }

    func deleteResponse<Response: Decodable>(_ path: String, accessToken: String? = nil) async throws -> Response {
        var request = try makeRequest(path: path, method: "DELETE", accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    func uploadImage(_ data: Data, fileName: String, mimeType: String, accessToken: String) async throws -> MediaUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(path: "/media", method: "POST", accessToken: accessToken)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(data: data, name: "file", fileName: fileName, mimeType: mimeType, boundary: boundary)
        return try await send(request)
    }

    private func makeRequest(path: String, method: String, accessToken: String?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401, let newToken = await performRefresh() {
                var retryRequest = request
                retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await urlSession.data(for: retryRequest)
                guard let retryHTTPResponse = retryResponse as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                guard (200..<300).contains(retryHTTPResponse.statusCode) else {
                    if let errorResponse = try? decoder.decode(ErrorResponse.self, from: retryData) {
                        throw APIError.server(errorResponse.error)
                    }
                    throw APIError.server("Request failed with status \(retryHTTPResponse.statusCode).")
                }
                return try decoder.decode(Response.self, from: retryData)
            }
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.server(errorResponse.error)
            }
            throw APIError.server("Request failed with status \(httpResponse.statusCode).")
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func sendWithoutBody(_ request: URLRequest) async throws {
        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401, let newToken = await performRefresh() {
                var retryRequest = request
                retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (_, retryResponse) = try await urlSession.data(for: retryRequest)
                guard let retryHTTPResponse = retryResponse as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                guard (200..<300).contains(retryHTTPResponse.statusCode) else {
                    throw APIError.server("Request failed with status \(retryHTTPResponse.statusCode).")
                }
                return
            }
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.server("Request failed with status \(httpResponse.statusCode).")
        }
    }

    private var refreshTask: Task<String?, Never>?

    private func performRefresh() async -> String? {
        if let existingTask = refreshTask {
            return await existingTask.value
        }
        let task = Task { [weak self] in
            defer { self?.refreshTask = nil }
            return await self?.onUnauthorized?()
        }
        refreshTask = task
        return await task.value
    }

    private func multipartBody(data: Data, name: String, fileName: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
