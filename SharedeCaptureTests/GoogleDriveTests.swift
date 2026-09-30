import XCTest
@testable import SharedeCapture

final class GoogleDriveTests: XCTestCase {
    func testDriveFolderLinks() {
        let id = "1AbC_def-1234567890"
        XCTAssertEqual(DriveFolderLink.folderID(from: "https://drive.google.com/drive/folders/\(id)?usp=sharing"), id)
        XCTAssertEqual(DriveFolderLink.folderID(from: "https://drive.google.com/open?id=\(id)"), id)
        XCTAssertNil(DriveFolderLink.folderID(from: "https://not-drive.google.com/drive/folders/\(id)"))
        XCTAssertNil(DriveFolderLink.folderID(from: "http://drive.google.com/drive/folders/\(id)"))
        XCTAssertNil(DriveFolderLink.folderID(from: "https://drive.google.com/file/d/\(id)/view"))
    }

    func testKeychainRoundTrip() throws {
        let key = "test-\(UUID().uuidString)"
        defer { DriveKeychain.delete(key) }
        try DriveKeychain.write("sample-client-id", for: key)
        XCTAssertEqual(DriveKeychain.read(key), "sample-client-id")
        try DriveKeychain.write("updated-client-id", for: key)
        XCTAssertEqual(DriveKeychain.read(key), "updated-client-id")
    }

    @MainActor
    func testOAuthLoopbackCallback() async throws {
        let server = try OAuthCallbackServer()
        let port = try await server.start()
        defer { server.cancel() }
        let callback = Task { try await server.waitForCallback() }
        let url = URL(string: "http://127.0.0.1:\(port)/?code=sample&state=expected")!
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let result = try await callback.value
        XCTAssertEqual(URLComponents(url: result, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value, "expected")
    }

    func testClientIDCheckClassifiesGoogleResponses() {
        let notFound = "https://accounts.google.com/signin/oauth/error?authError=Cg5pbnZhbGlkX2NsaWVudBIfVGhlIE9BdXRoIGNsaWVudCB3YXMgbm90IGZvdW5kLiCRAw&flowName=GeneralOAuthFlow"
        let wrongType = "https://accounts.google.com/signin/oauth/error?authError=ChVyZWRpcmVjdF91cmlfbWlzbWF0Y2g&flowName=GeneralOAuthFlow"
        XCTAssertEqual(ClientIDCheck.classify(statusCode: 302, location: notFound), .notFound)
        XCTAssertEqual(ClientIDCheck.classify(statusCode: 302, location: wrongType), .wrongType)
        XCTAssertEqual(ClientIDCheck.classify(statusCode: 302, location: "https://accounts.google.com/v3/signin/identifier?flowName=GeneralOAuthFlow"), .valid)
        XCTAssertEqual(ClientIDCheck.classify(statusCode: 500, location: ""), .unverified)
    }

    func testClientIDFormatCheck() async {
        let result = await ClientIDCheck.verify("not a client id")
        XCTAssertEqual(result, .badFormat)
        XCTAssertTrue(GoogleDriveService.isValidClientIDFormat("  123456789012-abcdefghijklmnop.apps.googleusercontent.com\n"))
    }

    func testClientSecretCheckClassifiesGoogleErrors() {
        XCTAssertEqual(ClientSecretCheck.classify(error: "invalid_grant"), .valid)
        XCTAssertEqual(ClientSecretCheck.classify(error: "invalid_client"), .invalid)
        XCTAssertEqual(ClientSecretCheck.classify(error: nil), .unverified)
        XCTAssertFalse(ClientSecretCheck.isValidFormat("short"))
        XCTAssertTrue(ClientSecretCheck.isValidFormat(" GOCSPX-abcdefghijklmnopqrstuvwx "))
    }

    @MainActor func testCallbackPageClosesOnlyOnSuccess() {
        XCTAssertTrue(OAuthCallbackServer.callbackPage(success: true).contains("window.close()"))
        XCTAssertFalse(OAuthCallbackServer.callbackPage(success: false).contains("window.close()"))
    }
}
