import Foundation
import Security

enum EndpointKeychain {
    static func account(for endpoint: String) throws -> String {
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw DictationError.recognition("Enter the full HTTPS transcription URL without credentials or a fragment.")
        }
        return url.absoluteString
    }
    static func key(for endpoint: String) throws -> String {
        let account = try account(for: endpoint)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "BetterWisprMobile",
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw DictationError.recognition("Could not read the API key from Keychain.")
        }
        return text
    }
    static func save(_ key: String, endpoint: String) throws {
        let account = try account(for: endpoint)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "BetterWisprMobile",
                                    kSecAttrAccount as String: account]
        // Update without deleting the previously saved credential on a failed replacement.
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query.merging(attributes) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw DictationError.recognition("Could not save the API key.") }
    }
}

final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum CloudTranscriber {
    static func transcribe(_ audio: URL, settings: DeviceSettings) async throws -> String {
        let endpoint = try EndpointKeychain.account(for: settings.endpoint)
        let key = try EndpointKeychain.key(for: endpoint)
        guard !settings.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.modelID.contains("\r"), !settings.modelID.contains("\n") else {
            throw DictationError.recognition("Enter a valid API model ID.")
        }
        let boundary = "BetterWispr-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", settings.modelID)
        field("language", String(settings.language.prefix(2)))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(try Data(contentsOf: audio)); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        guard let url = URL(string: endpoint) else { throw DictationError.recognition("Invalid endpoint.") }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DictationError.recognition("The transcription endpoint rejected the request. Check its URL, key and model. No other provider was used.")
        }
        struct Reply: Decodable { let text: String }
        return try JSONDecoder().decode(Reply.self, from: data).text
    }
}
