import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case message(String)
    case server(String)

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
        }
    }
}

struct APIClient {
    var baseURL: URL
    var urlSession: URLSession

    static let live = APIClient(
        baseURL: URL(string: "http://localhost:8080")!,
        urlSession: .shared
    )

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
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                throw APIError.server(errorResponse.error)
            }
            throw APIError.server("Request failed with status \(httpResponse.statusCode).")
        }
        return try decoder.decode(Response.self, from: data)
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
