import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, shortcuts, drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L10n.tr("Chung")
        case .shortcuts: L10n.tr("Phím tắt")
        case .drive: "Google Drive"
        }
    }

    var subtitle: String {
        switch self {
        case .general: L10n.tr("Chụp, lưu và quyền macOS")
        case .shortcuts: L10n.tr("Điều khiển từ mọi ứng dụng")
        case .drive: L10n.tr("Tài khoản và thư mục tải lên")
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .shortcuts: "keyboard"
        case .drive: "externaldrive"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var shortcuts: ShortcutSettings
    @EnvironmentObject private var drive: GoogleDriveService
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared
    let page: SettingsPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.system(size: 24, weight: .bold))
                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            ScrollView {
                Group {
                    switch page {
                    case .general: generalTab
                    case .shortcuts: shortcutsTab
                    case .drive: driveTab
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(title: L10n.tr("Ngôn ngữ")) {
                Picker(L10n.tr("Ngôn ngữ"), selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                Text(L10n.tr("Tiếng Anh là ngôn ngữ mặc định. Có thể đổi lại bất cứ lúc nào."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(title: L10n.tr("Khởi động")) {
                Toggle(L10n.tr("Mở Sharedee Tools khi đăng nhập"), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .disabled(!launchAtLogin.isSupported)
                if !launchAtLogin.isSupported {
                    Text(L10n.tr("Tính năng này cần macOS 13 trở lên."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if launchAtLogin.requiresApproval {
                    Text(L10n.tr("macOS cần bạn cho phép Sharedee Tools trong Mục đăng nhập."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(L10n.tr("Mở Mục đăng nhập…")) { launchAtLogin.openLoginItemsSettings() }
                } else {
                    Text(L10n.tr("App sẽ tự chạy trên thanh menu mỗi khi bạn bật máy và đăng nhập."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .onAppear { launchAtLogin.refresh() }

            SettingsSection(title: L10n.tr("Sau khi chụp")) {
                HStack {
                    Text(L10n.tr("Hành động mặc định"))
                    Spacer(minLength: 12)
                    Picker("", selection: $shortcuts.postCaptureAction) {
                        ForEach(PostCaptureAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Toggle(L10n.tr("Hiện con trỏ khi chụp toàn màn hình"), isOn: $shortcuts.includeCursor)
                HStack {
                    Text(L10n.tr("Hẹn giờ chụp"))
                    Spacer(minLength: 12)
                    Picker("", selection: $shortcuts.captureDelay) {
                        Text(L10n.tr("Không hẹn giờ")).tag(0)
                        Text(L10n.tr("3 giây")).tag(3)
                        Text(L10n.tr("5 giây")).tag(5)
                        Text(L10n.tr("10 giây")).tag(10)
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Text(L10n.tr("Thumbnail vẫn hiện để bạn chọn thao tác khác cho từng ảnh."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(title: L10n.tr("Thư mục lưu trên Mac")) {
                Text(shortcuts.saveFolderURL?.path ?? L10n.tr("Chưa chọn thư mục"))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(shortcuts.saveFolderURL == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(L10n.tr("Chọn thư mục…")) { chooseSaveFolder() }
                Text(L10n.tr("Nút Lưu sẽ dùng thư mục này. Nếu chưa chọn, app sẽ hỏi nơi lưu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(title: L10n.tr("Chụp cuộn")) {
                HStack {
                    Text(L10n.tr("Chiều dài tối đa"))
                    Spacer(minLength: 12)
                    Picker("", selection: $shortcuts.maxScrollHeight) {
                        ForEach(ShortcutSettings.maxScrollHeightOptions, id: \.self) { height in
                            Text(L10n.format("%@ px", height.formatted())).tag(height)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Text(L10n.tr("Kéo chọn vùng, bấm Chụp rồi tự cuộn bằng chuột hoặc bấm Tự cuộn trong vùng chọn. Tự cuộn cần quyền Trợ năng."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection(title: L10n.tr("Quyền macOS")) {
                HStack(spacing: 12) {
                    Button(L10n.tr("Ghi màn hình")) { openPrivacySettings("Privacy_ScreenCapture") }
                    Button(L10n.tr("Trợ năng")) { openPrivacySettings("Privacy_Accessibility") }
                }
                Button(L10n.tr("Khởi động lại Sharedee Tools")) {
                    AppRuntime.shared.restart()
                }
                Text(L10n.tr("Sau khi bật quyền Ghi màn hình, khởi động lại app một lần để macOS áp dụng quyền mới."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(title: L10n.tr("Thông tin")) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sharedee Tools")
                            .font(.system(size: 15, weight: .bold))
                        Text(AppInfo.versionDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(L10n.tr("Mã nguồn mở theo giấy phép Apache 2.0"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 16) {
                    if let url = AppInfo.repositoryURL { Link("GitHub ↗", destination: url) }
                    if let url = AppInfo.issuesURL { Link(L10n.tr("Báo lỗi / góp ý ↗"), destination: url) }
                    if let url = AppInfo.licenseURL { Link(L10n.tr("Giấy phép ↗"), destination: url) }
                }
                .font(.callout)
            }
        }
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.tr("Dùng thư mục này")
        if let current = shortcuts.saveFolderURL { panel.directoryURL = current }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        shortcuts.setSaveFolder(url)
    }

    private var driveTab: some View {
        DriveSettingsView(drive: drive)
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.tr("Nhấp vào ô rồi nhấn tổ hợp mới. Phím tắt hoạt động trong mọi ứng dụng khi Sharedee Tools đang chạy."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                ForEach(ShortcutAction.allCases) { action in
                    HStack(spacing: 12) {
                        Image(systemName: action.symbol)
                            .frame(width: 20)
                            .foregroundStyle(.mint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.title)
                                .font(.system(size: 13, weight: .medium))
                            if let error = shortcuts.errors[action] {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        ShortcutRecorder(shortcut: shortcuts.shortcut(for: action)) {
                            shortcuts.set($0, for: action)
                        }
                        .frame(width: 132, height: 34)
                    }
                    .padding(.vertical, 9)
                    if action != ShortcutAction.allCases.last { Divider() }
                }
            }

            HStack(spacing: 12) {
                Button(L10n.tr("Đặt lại phím tắt mặc định")) { shortcuts.resetToDefaults() }
                Button(L10n.tr("Dùng phím thay thế")) { shortcuts.useConflictFreePreset() }
            }
            Text(L10n.tr("Nếu trùng với phím của macOS hoặc ứng dụng khác, hãy đổi tổ hợp hoặc dùng bộ phím thay thế."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DriveSettingsView: View {
    @ObservedObject var drive: GoogleDriveService
    @State private var clientIDDraft = ""
    @State private var secretDraft = ""
    @State private var secretCheck: ClientSecretCheck?
    @State private var isCheckingSecret = false
    @State private var secretTask: Task<Void, Never>?
    @State private var isEditingClientID = false
    @State private var check: ClientIDCheck?
    @State private var isChecking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var confirmRemoval = false
    @State private var savedCheck: ClientIDCheck?
    @State private var folderLinkDraft = ""
    @State private var newFolderName = ""
    @State private var newFolderInCurrent = true
    @State private var isCreatingFolder = false
    @State private var localError = ""

    private var hasClientID: Bool { drive.isAvailable }
    private var showsClientIDForm: Bool { !hasClientID || isEditingClientID }
    private var canSaveDraft: Bool {
        (check == .valid || check == .unverified) && (secretCheck == .valid || secretCheck == .unverified)
    }
    private var missingSecret: Bool { drive.hasUserClientID && !drive.hasClientSecret }
    private var savedIDIsUnusable: Bool { savedCheck == .notFound || savedCheck == .wrongType || missingSecret }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(title: L10n.tr("Kết nối Google")) {
                DriveStep(number: 1, title: "OAuth Client ID", isDone: hasClientID && !isEditingClientID && !savedIDIsUnusable) {
                    if showsClientIDForm { clientIDForm } else { savedClientID }
                }
                Divider()
                DriveStep(number: 2, title: L10n.tr("Tài khoản Google"), isDone: drive.isConnected) {
                    accountStep
                }
                .opacity(hasClientID && !isEditingClientID && !savedIDIsUnusable ? 1 : 0.45)
                .disabled(!hasClientID || isEditingClientID || savedIDIsUnusable)
                if !localError.isEmpty {
                    Label(localError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .confirmationDialog(L10n.tr("Xóa Client ID đã lưu?"), isPresented: $confirmRemoval) {
                Button(L10n.tr("Xóa Client ID"), role: .destructive) {
                    drive.forgetClientID()
                    resetDraft()
                    folderLinkDraft = ""
                }
            } message: {
                Text(L10n.tr("Google Drive sẽ bị ngắt kết nối. Bạn có thể nhập lại Client ID bất cứ lúc nào."))
            }

            if showsClientIDForm {
                SettingsSection(title: L10n.tr("Cách tạo OAuth Client ID")) {
                    DriveSetupGuide(startsExpanded: !hasClientID)
                }
            }

            if drive.isConnected {
                SettingsSection(title: L10n.tr("Thư mục tải ảnh lên")) { folderSection }
            }
        }
    }

    // MARK: Step 1

    private var savedClientID: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(drive.maskedClientID ?? "")
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button(L10n.tr("Sửa")) {
                    clientIDDraft = drive.userClientID ?? ""
                    secretDraft = drive.clientSecret ?? ""
                    isEditingClientID = true
                    validateDraft(immediately: true)
                }
                if drive.hasUserClientID {
                    Button(L10n.tr("Xóa")) { confirmRemoval = true }
                }
            }
            .disabled(drive.isBusy)
            if missingSecret {
                Label(L10n.tr("Thiếu client secret. Bấm Sửa để nhập client secret của Client ID này."),
                      systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else { switch savedCheck {
            case .wrongType:
                Label(L10n.tr("Client ID tồn tại nhưng không phải loại Desktop app. Hãy tạo Client ID mới với Application type là Desktop app."),
                      systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .notFound:
                Label(L10n.tr("Google không tìm thấy Client ID này. Hãy kiểm tra lại hoặc tạo Client ID mới."),
                      systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                Text(drive.hasUserClientID ? L10n.tr("Client ID và client secret đã lưu trong Keychain") : L10n.tr("Dùng Client ID tích hợp sẵn trong app"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } }
        }
        .task(id: drive.activeClientID) { await checkSavedClientID() }
    }

    private func checkSavedClientID() async {
        guard let id = drive.activeClientID else {
            savedCheck = nil
            return
        }
        savedCheck = await ClientIDCheck.verify(id)
    }

    private var clientIDForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("xxxxxxxx.apps.googleusercontent.com", text: $clientIDDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .onChange(of: clientIDDraft) { _ in validateDraft(immediately: false) }
                    .onSubmit { if canSaveDraft { saveDraft() } }
                checkIcon.frame(width: 18)
            }
            checkMessage
            HStack(spacing: 8) {
                SecureField(L10n.tr("Client secret (GOCSPX-…)"), text: $secretDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .onChange(of: secretDraft) { _ in validateSecret(immediately: false) }
                    .onSubmit { if canSaveDraft { saveDraft() } }
                secretIcon.frame(width: 18)
            }
            secretMessage
            if isEditingClientID && drive.isConnected {
                Text(L10n.tr("Đổi sang Client ID khác sẽ ngắt kết nối Google Drive hiện tại."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(L10n.tr("Lưu Client ID")) { saveDraft() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSaveDraft || isChecking || isCheckingSecret || drive.isBusy)
                if isEditingClientID {
                    Button(L10n.tr("Hủy")) { resetDraft() }
                }
            }
        }
    }

    @ViewBuilder private var checkIcon: some View {
        if isChecking {
            ProgressView().controlSize(.small)
        } else {
            switch check {
            case .valid: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .unverified: Image(systemName: "questionmark.circle.fill").foregroundStyle(.yellow)
            case .badFormat, .notFound, .wrongType: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder private var checkMessage: some View {
        let text: String? = {
            if isChecking { return L10n.tr("Đang kiểm tra với Google…") }
            switch check {
            case .valid: return L10n.tr("Client ID hợp lệ.")
            case .badFormat: return L10n.tr("Sai định dạng. Client ID phải kết thúc bằng .apps.googleusercontent.com và không có khoảng trắng.")
            case .notFound: return L10n.tr("Google không tìm thấy Client ID này. Hãy kiểm tra lại hoặc tạo Client ID mới.")
            case .wrongType: return L10n.tr("Client ID tồn tại nhưng không phải loại Desktop app. Hãy tạo Client ID mới với Application type là Desktop app.")
            case .unverified: return L10n.tr("Không kiểm tra được với Google (có thể do mạng). Vẫn có thể lưu và thử kết nối.")
            case nil: return nil
            }
        }()
        if let text {
            Text(text)
                .font(.caption)
                .foregroundStyle(check == .valid || isChecking ? Color.secondary
                                 : check == .unverified ? Color.orange : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var secretIcon: some View {
        if isCheckingSecret {
            ProgressView().controlSize(.small)
        } else {
            switch secretCheck {
            case .valid: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .unverified: Image(systemName: "questionmark.circle.fill").foregroundStyle(.yellow)
            case .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder private var secretMessage: some View {
        let text: String? = {
            if isCheckingSecret { return L10n.tr("Đang kiểm tra client secret…") }
            switch secretCheck {
            case .valid: return L10n.tr("Client secret khớp với Client ID.")
            case .invalid: return L10n.tr("Client secret không khớp với Client ID này. Hãy sao chép lại từ Google Cloud.")
            case .unverified: return L10n.tr("Chưa kiểm tra được client secret. Vẫn có thể lưu và thử kết nối.")
            case nil: return check == .valid ? L10n.tr("Dán client secret của cùng Client ID (trong trang chi tiết client trên Google Cloud).") : nil
            }
        }()
        if let text {
            Text(text)
                .font(.caption)
                .foregroundStyle(secretCheck == .invalid ? Color.red : secretCheck == .unverified ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func validateSecret(immediately: Bool) {
        secretTask?.cancel()
        let id = clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            secretCheck = nil
            isCheckingSecret = false
            return
        }
        guard ClientSecretCheck.isValidFormat(secret) else {
            secretCheck = .invalid
            isCheckingSecret = false
            return
        }
        // The secret can only be checked against a Client ID that Google accepts.
        guard check == .valid else {
            secretCheck = check == .unverified ? .unverified : nil
            isCheckingSecret = false
            return
        }
        isCheckingSecret = true
        secretTask = Task {
            if !immediately { try? await Task.sleep(nanoseconds: 400_000_000) }
            guard !Task.isCancelled else { return }
            let result = await ClientSecretCheck.verify(clientID: id, secret: secret)
            guard !Task.isCancelled else { return }
            secretCheck = result
            isCheckingSecret = false
        }
    }

    private func validateDraft(immediately: Bool) {
        checkTask?.cancel()
        let value = clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            check = nil
            isChecking = false
            return
        }
        guard GoogleDriveService.isValidClientIDFormat(value) else {
            check = .badFormat
            isChecking = false
            return
        }
        isChecking = true
        checkTask = Task {
            if !immediately { try? await Task.sleep(nanoseconds: 400_000_000) }
            guard !Task.isCancelled else { return }
            let result = await ClientIDCheck.verify(value)
            guard !Task.isCancelled else { return }
            check = result
            isChecking = false
            validateSecret(immediately: true)
        }
    }

    private func saveDraft() {
        do {
            try drive.saveCredentials(clientID: clientIDDraft, secret: secretDraft)
            resetDraft()
            localError = ""
        } catch { localError = error.localizedDescription }
    }

    private func resetDraft() {
        checkTask?.cancel()
        secretTask?.cancel()
        clientIDDraft = ""
        secretDraft = ""
        secretCheck = nil
        isCheckingSecret = false
        check = nil
        isChecking = false
        isEditingClientID = false
    }

    // MARK: Step 2

    @ViewBuilder private var accountStep: some View {
        if drive.isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.tr("Đang chờ bạn đăng nhập trong trình duyệt…"))
                    .font(.callout)
                Spacer()
                Button(L10n.tr("Hủy")) { drive.cancelAuthorization() }
            }
        } else if drive.isConnected {
            HStack {
                Text(L10n.tr("Đã kết nối Google Drive"))
                    .font(.callout)
                Spacer()
                Button(L10n.tr("Ngắt kết nối")) {
                    drive.disconnect()
                    folderLinkDraft = ""
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button(L10n.tr("Kết nối Google Drive")) {
                    Task {
                        do {
                            try await drive.connect()
                            localError = ""
                        } catch { localError = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                Text(L10n.tr("Đăng nhập Google và cấp quyền. App sẽ tạo thư mục Sharedee Tools trên Drive."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Folder

    @ViewBuilder private var folderSection: some View {
        // Current folder
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.folderName.isEmpty ? L10n.tr("Thư mục Drive") : drive.folderName)
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.tr("Ảnh chụp sẽ được tải vào đây"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(L10n.tr("Mở trên Drive")) {
                if let url = URL(string: drive.folderLink) { NSWorkspace.shared.open(url) }
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

        // Folders the app can already use
        HStack {
            Text(L10n.tr("Thư mục của app"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if drive.isLoadingFolders {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await drive.refreshFolders() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("Tải lại danh sách"))
            }
        }
        VStack(spacing: 0) {
            if drive.folders.isEmpty && !drive.isLoadingFolders {
                Text(L10n.tr("Chưa có thư mục nào. Hãy tạo thư mục mới hoặc chọn từ Google Drive."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            ForEach(drive.folders) { folder in
                Button { drive.selectFolder(folder) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(folder.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if folder.id == drive.folderID {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if folder != drive.folders.last { Divider().padding(.leading, 34) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
        .task { await drive.refreshFolders() }

        // New folder
        HStack(spacing: 8) {
            TextField(L10n.tr("Tên thư mục mới"), text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { createFolder() }
            Picker("", selection: $newFolderInCurrent) {
                Text(L10n.format("Trong \"%@\"", drive.folderName.isEmpty ? L10n.tr("thư mục hiện tại") : drive.folderName)).tag(true)
                Text("My Drive").tag(false)
            }
            .labelsHidden()
            .frame(width: 190)
            Button(L10n.tr("Tạo thư mục")) { createFolder() }
                .disabled(isCreatingFolder || newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        }

        // Anything else on Drive goes through Google's picker.
        HStack(spacing: 8) {
            Button(L10n.tr("Chọn thư mục khác trên Google Drive…")) {
                Task {
                    do {
                        try await drive.signInAndChooseFolder(requestedLink: folderLinkDraft)
                        folderLinkDraft = ""
                        localError = ""
                        await drive.refreshFolders()
                    } catch { localError = error.localizedDescription }
                }
            }
            .disabled(drive.isBusy)
            TextField(L10n.tr("Hoặc dán link thư mục (tuỳ chọn)"), text: $folderLinkDraft)
                .textFieldStyle(.roundedBorder)
        }
        Text(L10n.tr("Cửa sổ chọn của Google không tạo được thư mục mới và sẽ yêu cầu đăng nhập lại. Muốn tạo thư mục bên trong một thư mục có sẵn, hãy chọn thư mục đó trước rồi tạo thư mục mới ở trên."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isCreatingFolder else { return }
        isCreatingFolder = true
        Task {
            defer { isCreatingFolder = false }
            do {
                try await drive.createFolder(named: name, parentID: newFolderInCurrent ? drive.folderID : nil)
                newFolderName = ""
                localError = ""
            } catch { localError = error.localizedDescription }
        }
    }
}

private struct DriveStep<Content: View>: View {
    let number: Int
    let title: String
    let isDone: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(isDone ? Color.green : Color.secondary.opacity(0.25))
                if isDone {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(.primary)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DriveSetupGuide: View {
    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let link: (title: String, url: String)?
    }

    @State private var isExpanded: Bool

    init(startsExpanded: Bool = false) {
        _isExpanded = State(initialValue: startsExpanded)
    }

    private var steps: [Step] {
        [
            Step(id: 1,
                 title: L10n.tr("Tạo project Google Cloud"),
                 detail: L10n.tr("Đăng nhập Google Cloud Console, tạo project mới (ví dụ: Sharedee Tools) và chọn project đó ở thanh trên cùng."),
                 link: (L10n.tr("Tạo project"), "https://console.cloud.google.com/projectcreate")),
            Step(id: 2,
                 title: L10n.tr("Bật Google Drive API"),
                 detail: L10n.tr("Mở trang Google Drive API và bấm Enable. App dùng API này để tạo thư mục và tải ảnh lên."),
                 link: (L10n.tr("Mở Google Drive API"), "https://console.cloud.google.com/apis/library/drive.googleapis.com")),
            Step(id: 3,
                 title: L10n.tr("Bật Google Picker API"),
                 detail: L10n.tr("Mở trang Google Picker API và bấm Enable. API này cho phép chọn thư mục Drive có sẵn."),
                 link: (L10n.tr("Mở Google Picker API"), "https://console.cloud.google.com/apis/library/picker.googleapis.com")),
            Step(id: 4,
                 title: L10n.tr("Cấu hình màn hình đồng ý OAuth"),
                 detail: L10n.tr("Trong Google Auth Platform, bấm Get started: nhập tên app và email hỗ trợ, chọn Audience là External, nhập email liên hệ rồi bấm Create."),
                 link: (L10n.tr("Mở Google Auth Platform"), "https://console.cloud.google.com/auth/overview")),
            Step(id: 5,
                 title: L10n.tr("Thêm tài khoản dùng thử"),
                 detail: L10n.tr("Vào Audience → Test users → Add users và thêm email Google bạn sẽ đăng nhập. Khi app ở chế độ Testing, chỉ các email này được kết nối."),
                 link: (L10n.tr("Mở Audience"), "https://console.cloud.google.com/auth/audience")),
            Step(id: 6,
                 title: L10n.tr("Tạo OAuth Client ID loại Desktop app"),
                 detail: L10n.tr("Vào Clients → Create client, chọn Application type là Desktop app, đặt tên rồi bấm Create. Sao chép Client ID (…apps.googleusercontent.com) và Client secret (GOCSPX-…)."),
                 link: (L10n.tr("Mở Clients"), "https://console.cloud.google.com/auth/clients")),
            Step(id: 7,
                 title: L10n.tr("Dán Client ID vào app"),
                 detail: L10n.tr("Dán Client ID và Client secret vào các ô phía trên, đợi cả hai hiện dấu tích xanh, bấm Lưu Client ID, rồi bấm Kết nối Google Drive và cấp quyền trong trình duyệt."),
                 link: nil)
        ]
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(step.id)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(step.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let link = step.link, let url = URL(string: link.url) {
                                Link(link.title + " ↗", destination: url)
                                    .font(.callout)
                            }
                        }
                    }
                }
                Text(L10n.tr("Mẹo: ở chế độ Testing, Google yêu cầu đăng nhập lại sau 7 ngày. Để kết nối lâu dài, vào Audience và bấm Publish app. Quyền drive.file mà app dùng không cần Google xét duyệt."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        } label: {
            Text(L10n.tr("Xem hướng dẫn từng bước (khoảng 5 phút)"))
                .font(.system(size: 13, weight: .medium))
        }
    }
}
