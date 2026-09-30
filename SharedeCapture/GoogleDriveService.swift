import AppKit
import CryptoKit
import Network
import Security
import SwiftUI

enum DriveFolderLink {
    static func folderID(from input: String) -> String? {
        guard let url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https",
              url.host == "drive.google.com" || url.host == "www.drive.google.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let id: String?
        if let index = parts.firstIndex(of: "folders"), parts.indices.contains(index + 1) {
            id = parts[index + 1]
        } else if parts.last == "open" {
            id = url.queryItems?.first { $0.name == "id" }?.value
        } else {
            id = nil
        }
        guard let id, id.count >= 10,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return id
    }

    static func url(for id: String) -> URL {
        URL(string: "https://drive.google.com/drive/folders/\(id)")!
    }
}

enum GoogleDriveError: LocalizedError {
    case missingClientID
    case missingClientSecret
    case invalidClientID
    case invalidFolderLink
    case notConnected
    case missingFolder
    case cancelled
    case timedOut
    case invalidResponse
    case folderNotWritable
    case google(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID: L10n.tr("Hãy lưu OAuth Client ID trong Cài đặt Google Drive trước.")
        case .invalidClientID: L10n.tr("Client ID không hợp lệ. Hãy dùng OAuth Client ID loại Desktop app.")
        case .missingClientSecret: L10n.tr("Hãy nhập client secret của OAuth Client ID loại Desktop app.")
        case .invalidFolderLink: L10n.tr("Liên kết phải là URL thư mục trên drive.google.com.")
        case .notConnected: L10n.tr("Hãy đăng nhập Google và chọn thư mục Drive trước.")
        case .missingFolder: L10n.tr("Hãy chọn thư mục Google Drive trước khi tải ảnh lên.")
        case .cancelled: L10n.tr("Đã hủy kết nối Google Drive.")
        case .timedOut: L10n.tr("Đăng nhập Google đã hết thời gian chờ. Hãy thử lại.")
        case .invalidResponse: L10n.tr("Google trả về dữ liệu không hợp lệ. Hãy thử lại.")
        case .folderNotWritable: L10n.tr("Thư mục Drive đã chọn không cho phép thêm tệp.")
        case .google(let message): "Google Drive: \(message)"
        }
    }
}

/// Result of asking Google whether a pasted OAuth Client ID can be used by this app.
enum ClientIDCheck: Equatable {
    case valid
    case badFormat
    case notFound
    case wrongType
    case unverified

    /// Starts Google's authorization flow without following redirects. Google answers an unusable
    /// client with a redirect to its error page whose `authError` payload names the OAuth error.
    static func verify(_ input: String, session: URLSession = .shared) async -> ClientIDCheck {
        let id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GoogleDriveService.isValidClientIDFormat(id) else { return .badFormat }
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "http://127.0.0.1:53682"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file")
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.httpMethod = "GET"
        let delegate = NoRedirectDelegate()
        guard let (_, response) = try? await session.data(for: request, delegate: delegate),
              let http = response as? HTTPURLResponse else { return .unverified }
        let location = http.value(forHTTPHeaderField: "Location") ?? ""
        return classify(statusCode: http.statusCode, location: location)
    }

    static func classify(statusCode: Int, location: String) -> ClientIDCheck {
        guard (300..<400).contains(statusCode) else {
            return statusCode == 200 ? .valid : .unverified
        }
        guard let url = URLComponents(string: location), url.path.contains("/oauth/error") else { return .valid }
        let payload = url.queryItems?.first { $0.name == "authError" }?.value ?? ""
        let text = decodeBase64URL(payload)
        if text.contains("invalid_client") || text.contains("deleted_client") { return .notFound }
        if text.contains("redirect_uri_mismatch") { return .wrongType }
        return .unverified
    }

    private static func decodeBase64URL(_ value: String) -> String {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}

/// Checks a client secret by redeeming a dummy code: Google rejects a wrong secret with
/// `invalid_client` before it looks at the code, and a right one with `invalid_grant`.
enum ClientSecretCheck: Equatable {
    case valid
    case invalid
    case unverified

    static func isValidFormat(_ value: String) -> Bool {
        let secret = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return secret.count >= 16 && !secret.contains(" ")
    }

    static func verify(clientID: String, secret: String, session: URLSession = .shared) async -> ClientSecretCheck {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "client_secret", value: secret.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "code", value: "sharedee-secret-check"),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: "http://127.0.0.1:53682")
        ]
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        guard let (data, _) = try? await session.data(for: request),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unverified }
        return classify(error: payload["error"] as? String)
    }

    static func classify(error: String?) -> ClientSecretCheck {
        switch error {
        case "invalid_grant": .valid
        case "invalid_client", "unauthorized_client": .invalid
        default: .unverified
        }
    }
}

enum DriveKeychain {
    private static let service = "com.sharedecapture.app.google-drive"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for key: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let data = Data(value.utf8)
        let updated = SecItemUpdate(identity as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw GoogleDriveError.google(L10n.format("Không thể cập nhật Keychain (%d).", updated))
        }
        var item = identity
        item[kSecValueData as String] = data
        let result = SecItemAdd(item as CFDictionary, nil)
        guard result == errSecSuccess else { throw GoogleDriveError.google(L10n.format("Không thể lưu vào Keychain (%d).", result)) }
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class GoogleDriveService: ObservableObject {
    var isAvailable: Bool { clientID != nil }
    var hasUserClientID: Bool { DriveKeychain.read(Self.clientIDKey) != nil }
    var userClientID: String? { DriveKeychain.read(Self.clientIDKey) }
    var activeClientID: String? { clientID }
    /// The secret saved with a user-entered Client ID, or the one built in with the bundled Client ID.
    var clientSecret: String? {
        if let saved = DriveKeychain.read(Self.clientSecretKey) { return saved }
        guard !hasUserClientID,
              let bundled = Bundle.main.object(forInfoDictionaryKey: Self.bundledClientSecretKey) as? String,
              ClientSecretCheck.isValidFormat(bundled) else { return nil }
        return bundled
    }
    var hasClientSecret: Bool { clientSecret != nil }
    /// The active Client ID shortened for display, e.g. "1234567…abcd.apps.googleusercontent.com".
    var maskedClientID: String? {
        guard let id = clientID else { return nil }
        let suffix = ".apps.googleusercontent.com"
        let head = id.hasSuffix(suffix) ? String(id.dropLast(suffix.count)) : id
        guard head.count > 12 else { return id }
        return "\(head.prefix(7))…\(head.suffix(4))\(suffix)"
    }

    nonisolated static func isValidClientIDFormat(_ value: String) -> Bool {
        isValidClientID(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    @Published private(set) var isConnected: Bool
    @Published private(set) var folderLink: String
    @Published private(set) var folderName: String
    @Published private(set) var folders: [DriveFolder] = []
    @Published private(set) var isLoadingFolders = false
    var folderID: String? { DriveFolderLink.folderID(from: folderLink) }
    @Published private(set) var status: String
    @Published private(set) var isBusy = false

    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    private var activeServer: OAuthCallbackServer?
    private static let scope = "https://www.googleapis.com/auth/drive.file"
    private static let clientIDKey = "oauth-client-id"
    private static let clientSecretKey = "oauth-client-secret"
    private static let refreshTokenKey = "refresh-token"
    private static let refreshTokenClientIDKey = "refresh-token-client-id"
    private static let folderLinkKey = "googleDriveFolderLink"
    private static let folderNameKey = "googleDriveFolderName"
    private static let folderMimeType = "application/vnd.google-apps.folder"
    private static let bundledClientIDKey = "SharedeeGoogleOAuthClientID"
    private static let bundledClientSecretKey = "SharedeeGoogleOAuthClientSecret"
    private static let defaultFolderName = "Sharedee Tools"

    private var clientID: String? {
        let legacy = DriveKeychain.read(Self.clientIDKey)
        if DriveKeychain.read(Self.refreshTokenKey) != nil {
            if let stored = DriveKeychain.read(Self.refreshTokenClientIDKey),
               Self.isValidClientID(stored) { return stored }
            if let legacy, Self.isValidClientID(legacy) { return legacy }
        }
        if let legacy, Self.isValidClientID(legacy) { return legacy }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: Self.bundledClientIDKey) as? String,
           Self.isValidClientID(bundled) { return bundled }
        return nil
    }

    nonisolated private static func isValidClientID(_ value: String) -> Bool {
        value.hasSuffix(".apps.googleusercontent.com") && value.count > 30 && !value.contains(" ")
    }

    init() {
        let connected = DriveKeychain.read(Self.refreshTokenKey) != nil
        let savedFolder = UserDefaults.standard.string(forKey: Self.folderLinkKey) ?? ""
        let hasConnection = connected && !savedFolder.isEmpty
        isConnected = hasConnection
        folderLink = savedFolder
        folderName = UserDefaults.standard.string(forKey: Self.folderNameKey) ?? ""
        status = hasConnection ? L10n.tr("Đã kết nối Google Drive") : L10n.tr("Chưa kết nối Google Drive")
    }

    func refreshLanguage() {
        guard !isBusy else { return }
        status = isConnected ? L10n.tr("Đã kết nối Google Drive") : L10n.tr("Chưa kết nối Google Drive")
    }

    func saveCredentials(clientID input: String, secret secretInput: String) throws {
        guard !isBusy else { return }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidClientID(value) else { throw GoogleDriveError.invalidClientID }
        guard ClientSecretCheck.isValidFormat(secret) else { throw GoogleDriveError.missingClientSecret }
        let current = clientID
        try DriveKeychain.write(value, for: Self.clientIDKey)
        try DriveKeychain.write(secret, for: Self.clientSecretKey)
        if current != value { disconnect() }
        status = L10n.tr("Đã lưu Client ID trong Keychain")
    }

    func forgetClientID() {
        guard !isBusy else { return }
        disconnect()
        DriveKeychain.delete(Self.clientIDKey)
        DriveKeychain.delete(Self.clientSecretKey)
        status = L10n.tr("Đã xóa Client ID đã lưu")
    }

    func disconnect() {
        activeServer?.cancel()
        activeServer = nil
        DriveKeychain.delete(Self.refreshTokenKey)
        DriveKeychain.delete(Self.refreshTokenClientIDKey)
        accessToken = nil
        accessTokenExpiry = .distantPast
        isConnected = false
        folderLink = ""
        folderName = ""
        folders = []
        UserDefaults.standard.removeObject(forKey: Self.folderLinkKey)
        UserDefaults.standard.removeObject(forKey: Self.folderNameKey)
        status = L10n.tr("Đã ngắt kết nối Google Drive")
    }

    func cancelAuthorization() {
        activeServer?.cancel()
        status = L10n.tr("Đã hủy kết nối Google Drive")
    }

    /// Connects the account and prepares an app-owned folder without asking for a folder link.
    func connect() async throws {
        guard !isBusy else { return }
        guard let clientID else { throw GoogleDriveError.missingClientID }
        isBusy = true
        defer { isBusy = false }
        status = L10n.tr("Đang mở Google để đăng nhập…")
        do {
            let authorization = try await authorize(clientID: clientID, chooseFolder: false)
            let token = try await exchangeCode(authorization.code, clientID: clientID,
                                               redirectURI: authorization.redirectURI,
                                               verifier: authorization.verifier)
            let folder = try await findOrCreateDefaultFolder(accessToken: token.access_token)
            try finishConnection(token: token, folder: folder, clientID: clientID)
        } catch {
            status = error.localizedDescription
            throw error
        }
    }

    func signInAndChooseFolder(requestedLink: String) async throws {
        guard !isBusy else { return }
        guard let clientID else { throw GoogleDriveError.missingClientID }
        let trimmed = requestedLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedID: String?
        if trimmed.isEmpty { requestedID = nil }
        else {
            guard let id = DriveFolderLink.folderID(from: trimmed) else { throw GoogleDriveError.invalidFolderLink }
            requestedID = id
        }

        isBusy = true
        defer { isBusy = false }
        status = L10n.tr("Đang mở Google để chọn thư mục…")
        do {
            let authorization = try await authorize(clientID: clientID, chooseFolder: true,
                                                    requestedID: requestedID)
            guard let selectedID = authorization.pickedFolderID else {
                throw GoogleDriveError.cancelled
            }
            if let requestedID, selectedID != requestedID { throw GoogleDriveError.invalidFolderLink }
            let token = try await exchangeCode(authorization.code, clientID: clientID,
                                               redirectURI: authorization.redirectURI,
                                               verifier: authorization.verifier)
            let folder = try await fetchFolder(selectedID, accessToken: token.access_token)
            guard folder.mimeType == "application/vnd.google-apps.folder" else { throw GoogleDriveError.invalidFolderLink }
            guard folder.capabilities?.canAddChildren == true else { throw GoogleDriveError.folderNotWritable }
            try finishConnection(token: token, folder: folder, clientID: clientID)
        } catch {
            status = error.localizedDescription
            throw error
        }
    }

    private struct AuthorizationCode {
        let code: String
        let redirectURI: String
        let verifier: String
        let pickedFolderID: String?
    }

    private func authorize(clientID: String, chooseFolder: Bool,
                           requestedID: String? = nil) async throws -> AuthorizationCode {
        let server = try OAuthCallbackServer()
        activeServer = server
        defer { activeServer = nil }
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let verifier = Self.randomURLSafeString()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafeString()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if chooseFolder {
            items.append(contentsOf: [
                URLQueryItem(name: "trigger_onepick", value: "true"),
                URLQueryItem(name: "allow_folder_selection", value: "true"),
                URLQueryItem(name: "mimetypes", value: "application/vnd.google-apps.folder")
            ])
            if let requestedID { items.append(URLQueryItem(name: "file_ids", value: requestedID)) }
        }
        components.queryItems = items
        guard let authURL = components.url, NSWorkspace.shared.open(authURL) else {
            server.cancel()
            throw GoogleDriveError.invalidResponse
        }
        let callback = try await server.waitForCallback()
        NSApp.activate(ignoringOtherApps: true)
        let response = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        func parameter(_ name: String) -> String? { response?.queryItems?.first { $0.name == name }?.value }
        guard parameter("state") == state else { throw GoogleDriveError.invalidResponse }
        if let error = parameter("error") {
            throw error == "access_denied" ? GoogleDriveError.cancelled : GoogleDriveError.google(error)
        }
        guard let code = parameter("code") else { throw GoogleDriveError.cancelled }
        return AuthorizationCode(code: code, redirectURI: redirectURI, verifier: verifier,
                                 pickedFolderID: parameter("picked_file_ids")?.split(separator: ",").first.map(String.init))
    }

    private func finishConnection(token: OAuthToken, folder: DriveFile, clientID: String) throws {
        guard let folderID = folder.id else { throw GoogleDriveError.invalidResponse }
        if let refresh = token.refresh_token {
            try DriveKeychain.write(clientID, for: Self.refreshTokenClientIDKey)
            try DriveKeychain.write(refresh, for: Self.refreshTokenKey)
        } else {
            let existingClientID = DriveKeychain.read(Self.refreshTokenClientIDKey)
                ?? DriveKeychain.read(Self.clientIDKey)
            guard DriveKeychain.read(Self.refreshTokenKey) != nil,
                  existingClientID == clientID else { throw GoogleDriveError.invalidResponse }
            try DriveKeychain.write(clientID, for: Self.refreshTokenClientIDKey)
        }
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
        isConnected = true
        setCurrentFolder(id: folderID, name: folder.name ?? folderID)
        status = L10n.format("Đã kết nối thư mục %@", folder.name ?? folderID)
    }

    private func setCurrentFolder(id: String, name: String) {
        folderLink = DriveFolderLink.url(for: id).absoluteString
        folderName = name
        UserDefaults.standard.set(folderLink, forKey: Self.folderLinkKey)
        UserDefaults.standard.set(name, forKey: Self.folderNameKey)
    }

    // MARK: Folders the app can use

    /// Lists folders this app can see. With the `drive.file` scope that is every folder the app
    /// created plus folders the user picked in Google's picker.
    func refreshFolders() async {
        guard isConnected, !isLoadingFolders else { return }
        isLoadingFolders = true
        defer { isLoadingFolders = false }
        do {
            let token = try await validAccessToken()
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            components.queryItems = [
                URLQueryItem(name: "q", value: "mimeType = '\(Self.folderMimeType)' and trashed = false"),
                URLQueryItem(name: "fields", value: "files(id,name,mimeType,capabilities(canAddChildren))"),
                URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
                URLQueryItem(name: "pageSize", value: "50"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.check(response, data: data)
            let list = try JSONDecoder().decode(DriveFileList.self, from: data)
            folders = list.files.compactMap { file in
                guard let id = file.id, file.capabilities?.canAddChildren == true else { return nil }
                return DriveFolder(id: id, name: file.name ?? id)
            }
            if let current = folderID, let match = folders.first(where: { $0.id == current }), match.name != folderName {
                setCurrentFolder(id: match.id, name: match.name)
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func selectFolder(_ folder: DriveFolder) {
        guard isConnected else { return }
        setCurrentFolder(id: folder.id, name: folder.name)
        status = L10n.format("Ảnh sẽ được tải vào thư mục %@", folder.name)
    }

    /// Creates a folder inside `parentID` (or My Drive when nil) and makes it the upload folder.
    func createFolder(named rawName: String, parentID: String?) async throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id,name,mimeType,capabilities(canAddChildren)&supportsAllDrives=true")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var metadata: [String: Any] = ["name": name, "mimeType": Self.folderMimeType]
        if let parentID { metadata["parents"] = [parentID] }
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        let folder = try JSONDecoder().decode(DriveFile.self, from: data)
        guard let id = folder.id else { throw GoogleDriveError.invalidResponse }
        let created = DriveFolder(id: id, name: folder.name ?? name)
        folders.removeAll { $0.id == id }
        folders.insert(created, at: 0)
        selectFolder(created)
        status = L10n.format("Đã tạo thư mục %@", created.name)
    }

    private func findOrCreateDefaultFolder(accessToken: String) async throws -> DriveFile {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name = '\(Self.defaultFolderName)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,capabilities(canAddChildren))"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        var listRequest = URLRequest(url: components.url!)
        listRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
        try Self.check(listResponse, data: listData)
        let existing = try JSONDecoder().decode(DriveFileList.self, from: listData)
        if let folder = existing.files.first(where: { $0.capabilities?.canAddChildren == true }) {
            return folder
        }

        var createRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id,name,mimeType,capabilities(canAddChildren)")!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": Self.defaultFolderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])
        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
        try Self.check(createResponse, data: createData)
        return try JSONDecoder().decode(DriveFile.self, from: createData)
    }

    func uploadPNG(_ data: Data, name: String) async throws -> URL {
        guard isConnected else { throw GoogleDriveError.notConnected }
        guard let folderID = DriveFolderLink.folderID(from: folderLink) else { throw GoogleDriveError.missingFolder }
        let metadata = try JSONSerialization.data(withJSONObject: [
            "name": name, "mimeType": "image/png", "parents": [folderID]
        ])
        let sessionURL = try await startUploadSession(metadata: metadata, imageSize: data.count)

        var upload = URLRequest(url: sessionURL)
        upload.httpMethod = "PUT"
        upload.setValue("image/png", forHTTPHeaderField: "Content-Type")
        upload.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        upload.httpBody = data
        let (resultData, response) = try await URLSession.shared.data(for: upload)
        try Self.check(response, data: resultData)
        let file = try JSONDecoder().decode(DriveFile.self, from: resultData)
        guard let id = file.id else { throw GoogleDriveError.invalidResponse }
        return URL(string: file.webViewLink ?? "https://drive.google.com/file/d/\(id)/view")!
    }

    private func startUploadSession(metadata: Data, imageSize: Int) async throws -> URL {
        for attempt in 0..<2 {
            let token = try await validAccessToken(forceRefresh: attempt > 0)
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink&supportsAllDrives=true")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("image/png", forHTTPHeaderField: "X-Upload-Content-Type")
            request.setValue(String(imageSize), forHTTPHeaderField: "X-Upload-Content-Length")
            request.httpBody = metadata
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 401 && attempt == 0 { continue }
            try Self.check(response, data: data)
            guard let session = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
                  let sessionURL = URL(string: session), sessionURL.scheme == "https",
                  sessionURL.host == "www.googleapis.com" else { throw GoogleDriveError.invalidResponse }
            return sessionURL
        }
        throw GoogleDriveError.invalidResponse
    }

    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let accessToken, Date() < accessTokenExpiry { return accessToken }
        guard let clientID,
              let refresh = DriveKeychain.read(Self.refreshTokenKey) else { throw GoogleDriveError.notConnected }
        let body = Self.formBody(withSecret([
            "client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"
        ]))
        let token: OAuthToken = try await Self.postToken(body)
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
        return token.access_token
    }

    private func exchangeCode(_ code: String, clientID: String,
                              redirectURI: String, verifier: String) async throws -> OAuthToken {
        try await Self.postToken(Self.formBody(withSecret([
            "client_id": clientID, "code": code, "code_verifier": verifier,
            "redirect_uri": redirectURI, "grant_type": "authorization_code"
        ])))
    }

    /// Google requires the (non-confidential) client secret of Desktop app clients on token requests.
    private func withSecret(_ values: [String: String]) -> [String: String] {
        guard let secret = clientSecret else { return values }
        return values.merging(["client_secret": secret]) { current, _ in current }
    }

    private func fetchFolder(_ id: String, accessToken: String) async throws -> DriveFile {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,capabilities(canAddChildren)"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(DriveFile.self, from: data)
    }

    private static func postToken(_ body: Data) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GoogleDriveError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = payload?["error"] as? [String: Any]
            let message = detail?["message"] as? String
                ?? payload?["error_description"] as? String
                ?? payload?["error"] as? String
                ?? "HTTP \(http.statusCode)"
            throw GoogleDriveError.google(message)
        }
    }

    private static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct OAuthToken: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

struct DriveFolder: Identifiable, Equatable {
    let id: String
    let name: String
}

private struct DriveFile: Decodable {
    let id: String?
    let name: String?
    let mimeType: String?
    let webViewLink: String?
    let capabilities: Capabilities?

    struct Capabilities: Decodable { let canAddChildren: Bool? }
}

private struct DriveFileList: Decodable {
    let files: [DriveFile]
}

@MainActor
final class OAuthCallbackServer {
    private let listener: NWListener
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var port: UInt16 = 0
    private var wasCancelled = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener.port?.rawValue else {
                            self.readyContinuation?.resume(throwing: GoogleDriveError.invalidResponse)
                            self.readyContinuation = nil
                            return
                        }
                        self.port = port
                        self.readyContinuation?.resume(returning: port)
                        self.readyContinuation = nil
                    case .failed(let error):
                        self.readyContinuation?.resume(throwing: error)
                        self.readyContinuation = nil
                        self.callbackContinuation?.resume(throwing: error)
                        self.callbackContinuation = nil
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.receive(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func waitForCallback() async throws -> URL {
        if wasCancelled { throw GoogleDriveError.cancelled }
        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
                self?.finish(.failure(GoogleDriveError.timedOut))
            }
        }
    }

    func cancel() {
        wasCancelled = true
        readyContinuation?.resume(throwing: GoogleDriveError.cancelled)
        readyContinuation = nil
        listener.cancel()
        finish(.failure(GoogleDriveError.cancelled))
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .components(separatedBy: "\r\n").first ?? ""
                let words = line.split(separator: " ")
                guard words.count >= 2, words[0] == "GET",
                      let url = URL(string: "http://127.0.0.1:\(self.port)\(words[1])") else {
                    connection.cancel()
                    return
                }
                let failed = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.contains { $0.name == "error" } ?? false
                let body = Data(Self.callbackPage(success: !failed).utf8)
                let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: header + body, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                self.finish(.success(url))
            }
        }
    }

    /// Page shown in the browser after Google redirects back. It tries to close its own tab;
    /// browsers only allow that for some tabs, so the text also tells the user to switch back.
    static func callbackPage(success: Bool) -> String {
        let title = success ? L10n.tr("Đã kết nối Google Drive") : L10n.tr("Chưa kết nối được Google Drive")
        let detail = success
            ? L10n.tr("Sharedee Tools đã nhận quyền truy cập. Tab này sẽ tự đóng; nếu không, bạn có thể đóng nó và quay lại app.")
            : L10n.tr("Đăng nhập đã bị hủy hoặc bị từ chối. Hãy quay lại Sharedee Tools để thử lại.")
        let icon = success ? "&#10003;" : "&#10005;"
        let color = success ? "#0f8b8d" : "#d64545"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>Sharedee Tools</title>
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center;
               font: 15px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; background: Canvas; color: CanvasText; }
        .card { max-width: 420px; padding: 40px 32px; text-align: center; }
        .icon { width: 64px; height: 64px; margin: 0 auto 20px; border-radius: 50%; background: \(color);
                color: #fff; font-size: 34px; line-height: 64px; }
        h1 { font-size: 22px; margin: 0 0 8px; }
        p { margin: 0; opacity: .7; }
        </style></head>
        <body><div class="card"><div class="icon">\(icon)</div><h1>\(title)</h1><p>\(detail)</p></div>
        <script>\(success ? "setTimeout(function () { window.close(); }, 1500);" : "")</script>
        </body></html>
        """
    }

    private func finish(_ result: Result<URL, Error>) {
        listener.cancel()
        guard let callbackContinuation else { return }
        self.callbackContinuation = nil
        callbackContinuation.resume(with: result)
    }
}
