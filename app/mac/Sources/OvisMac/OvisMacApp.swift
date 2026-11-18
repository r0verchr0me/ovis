import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

@main
struct OvisMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = Model()

    var body: some Scene {
        // not "main", the setup window's id before: macOS keeps a window's frame by its id, and that one is 520 wide
        Window("Ovis", id: "ovis") {
            MainView()
                .environmentObject(model)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands { OvisCommands(model: model) }

        Window(L("Phone Setup", "휴대폰 연결"), id: "setup") {
            ContentView()
                .environmentObject(model)
                .frame(width: 520)
                .task { if !model.busy { await model.refresh() } }
        }
        .windowResizability(.contentSize)
    }
}

struct MainView: View {
    @EnvironmentObject private var model: Model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let origin = model.webOrigin {
                if case .remote(let serverId) = model.serverKind {
                    WebPage(origin: origin, model: model, remoteServerId: serverId).id(origin)
                } else {
                    WebPage(origin: origin, model: model).id(origin)
                }
            } else if model.phase == .checking {
                ProgressView(L("Checking this Mac…", "이 Mac을 확인하는 중…"))
            } else {
                ScrollView { ContentView().frame(width: 520).padding(.vertical, 24) }
            }
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .task {
            LaunchAgent.rotateLog()
            await model.refresh()
            await model.monitor()
        }
        .onChange(of: model.phoneSetupRequested) { requested in
            guard requested else { return }
            model.phoneSetupRequested = false
            openWindow(id: "setup")
        }
        // Pause monitor when window is not key for CPU efficiency
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if model.serverKind != .local {
                // For remote servers, we can be less aggressive with monitoring
            }
        }
    }
}

struct OvisCommands: Commands {
    let model: Model

    var body: some Commands {
        CommandGroup(after: .appInfo) { PhoneSetupItem() }
        CommandGroup(replacing: .newItem) {
            OpenInBrowserItem(model: model)
            AddRemoteServerItem(model: model)
        }
        CommandGroup(before: .toolbar) {
            ReloadItem(model: model)
            PushNotificationsItem(model: model)
        }
    }
}

/// No Cmd+Shift letter here or below: the page's own shortcuts are Cmd+Shift ones (src/lib/shortcuts.ts).
private struct PhoneSetupItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(L("Phone Setup…", "휴대폰 연결…")) { openWindow(id: "setup") }
    }
}

private struct OpenInBrowserItem: View {
    @ObservedObject var model: Model

    var body: some View {
        Button(L("Open in Browser", "브라우저에서 열기")) { model.openInBrowser() }
            .disabled(model.webOrigin == nil)
    }
}

private struct ReloadItem: View {
    @ObservedObject var model: Model

    var body: some View {
        Button(L("Reload", "새로고침")) { model.reload() }
            .keyboardShortcut("r")
            .disabled(model.webOrigin == nil)
    }
}

private struct PushNotificationsItem: View {
    @ObservedObject var model: Model

    var body: some View {
        Button(model.isPushSubscribed ? L("Disable Push Notifications", "푸시 알림 끄기") : L("Enable Push Notifications…", "푸시 알림 켜기…")) {
            Task { await model.togglePushNotifications() }
        }
        .disabled(model.webOrigin == nil)
    }
}

private struct AddRemoteServerItem: View {
    @ObservedObject var model: Model
    @State private var showAddServer = false
    @State private var addServerURL = ""
    @State private var addServerName = ""
    @State private var addServerError = ""

    var body: some View {
        Button(L("Add Remote Server…", "원격 서버 추가…")) { showAddServer = true }
            .sheet(isPresented: $showAddServer) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ovis").font(.title.bold())
                            Text(L("Add Remote Server", "원격 서버 추가")).foregroundStyle(.secondary)
                        }
                    }
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Paste a pairing link from Ovis on another device.", "다른 기기의 Ovis에서 페어링 링크를 붙여넣으세요."))
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Pairing Link", "페어링 링크")).font(.caption).foregroundStyle(.secondary)
                            TextField("https://app.ovis.sh/s/...#offer=...", text: $addServerURL)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: addServerURL) { _, _ in addServerError = "" }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Name (optional)", "이름 (선택)")).font(.caption).foregroundStyle(.secondary)
                            TextField(L("My Server", "내 서버"), text: $addServerName)
                                .textFieldStyle(.roundedBorder)
                        }

                        if !addServerError.isEmpty {
                            Text(addServerError).font(.caption).foregroundStyle(.red)
                        }

                        HStack {
                            Spacer()
                            Button(L("Cancel", "취소")) { showAddServer = false }
                            Button(L("Add", "추가")) {
                                if let server = ServerStore.Server.from(offerURL: addServerURL, name: addServerName.isEmpty ? nil : addServerName) {
                                    ServerStore.add(server)
                                    Task { await model.connectToRemoteServer(server) }
                                    showAddServer = false
                                } else {
                                    addServerError = L("Invalid pairing link. Make sure it contains #offer=...", "유효하지 않은 페어링 링크입니다. #offer=...가 포함되어 있는지 확인하세요.")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(addServerURL.isEmpty)
                        }
                    }
                }
                .padding(24)
                .frame(width: 520)
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @EnvironmentObject private var model: Model
    @State private var confirmRemove = false
    @State private var showAddServer = false
    @State private var addServerURL = ""
    @State private var addServerName = ""
    @State private var addServerError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ovis").font(.title.bold())
                    Text(L("Your coding agents, on your phone", "코딩 에이전트를 휴대폰에서")).foregroundStyle(.secondary)
                }
            }
            Divider()
            switch model.phase {
            case .checking:
                ProgressView(L("Checking this Mac…", "이 Mac을 확인하는 중…")).frame(maxWidth: .infinity, minHeight: 160)
            case .notInstalled:
                notInstalled
            case let .working(title):
                working(title)
            case let .failed(message):
                failed(message)
            case .installed:
                installed
            }
        }
        .padding(24)
        .confirmationDialog(L("Remove the Ovis server from this Mac?", "이 Mac에서 Ovis 서버를 제거할까요?"), isPresented: $confirmRemove) {
            Button(L("Remove", "제거"), role: .destructive) { Task { await model.uninstall() } }
        } message: {
            Text(L("herdr, Bun and Node stay, and herdr keeps running with your agents.", "herdr, Bun, Node는 남고, herdr와 에이전트는 계속 실행됩니다."))
        }
        .sheet(isPresented: $showAddServer) {
            addServerSheet
                .frame(width: 520)
                .padding(24)
        }
    }

    private var notInstalled: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Set up this Mac for Ovis", "이 Mac을 Ovis에 연결할 준비를 합니다")).font(.headline)
            Text(L("This installs herdr, Bun, Node and the Ovis server for your user only, with no administrator password, and starts herdr when you log in. Then scan the QR code with Ovis on your phone.",
                   "herdr, Bun, Node, Ovis 서버를 내 사용자 계정에만 설치합니다(관리자 비밀번호 필요 없음). 로그인할 때 herdr가 자동으로 켜집니다. 설치가 끝나면 휴대폰의 Ovis로 QR 코드를 찍으면 됩니다."))
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Install", "설치")) { Task { await model.install() } }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
    }

    private func working(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(title).font(.headline)
            }
            logView
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.headline)
            logView
            HStack {
                Button(L("Try again", "다시 시도")) { Task { await model.retry() } }.buttonStyle(.borderedProminent)
                Button(L("Copy the log", "오류 내용 복사")) { model.copyLog() }
                Spacer()
                Button(L("Get help", "도움 받기")) { model.open(Ovis.support) }
            }
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.logText.isEmpty ? " " : model.logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                Color.clear.frame(height: 1).id("end")
            }
            .frame(height: 220)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: model.log.count) { _ in proxy.scrollTo("end") }
        }
    }

    private var installed: some View {
        let status = model.status
        let isRemote = model.serverKind != .local
        let remoteServer = model.remoteServer

        return VStack(alignment: .leading, spacing: 16) {
            // Server selector
            HStack(spacing: 12) {
                // Local server button
                Button {
                    if model.serverKind != .local {
                        Task { await model.switchToLocal() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(isRemote ? .gray : (status?.running == true ? .green : .orange)).frame(width: 8, height: 8)
                        Text(L("This Mac", "이 Mac")).font(.headline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isRemote ? Color.clear : Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!isRemote)

                // Remote servers
                ForEach(ServerStore.servers) { server in
                    Button {
                        if model.serverKind != .remote(id: server.id) {
                            Task { await model.connectToRemoteServer(server) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(model.serverKind == .remote(id: server.id) ? .green : .gray).frame(width: 8, height: 8)
                            Text(server.name).font(.headline).lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(model.serverKind == .remote(id: server.id) ? Color.accentColor.opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.serverKind == .remote(id: server.id))
                    .contextMenu {
                        Button(L("Remove", "제거"), role: .destructive) {
                            model.removeRemoteServer(server.id)
                        }
                    }
                }

                Spacer()

                Button {
                    addServerURL = ""
                    addServerName = ""
                    addServerError = ""
                    showAddServer = true
                } label: {
                    Image(systemName: "plus").font(.headline)
                }
                .buttonStyle(.bordered)
                .help(L("Add remote server", "원격 서버 추가"))

                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("Check again", "다시 확인"))
                    .accessibilityLabel(L("Check again", "다시 확인"))
            }

            if isRemote, let server = remoteServer {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Connected to \(server.name)", "\(server.name)에 연결됨")).font(.headline)
                    Text(server.origin).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button(L("Disconnect", "연결 해제")) { Task { await model.switchToLocal() } }
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if !isRemote {
                if status?.running == true { phone(status) }
                HStack {
                    Button(status?.running == true ? L("Restart", "다시 시작") : L("Start", "시작")) { Task { await model.restart() } }
                    Spacer()
                    Button(L("Remove…", "제거…")) { confirmRemove = true }
                }
            }
        }
    }

    private var addServerSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ovis").font(.title.bold())
                    Text(L("Add Remote Server", "원격 서버 추가")).foregroundStyle(.secondary)
                }
            }
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(L("Paste a pairing link from Ovis on another device.", "다른 기기의 Ovis에서 페어링 링크를 붙여넣으세요."))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Pairing Link", "페어링 링크")).font(.caption).foregroundStyle(.secondary)
                    TextField("https://app.ovis.sh/s/...#offer=...", text: $addServerURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: addServerURL) { _, _ in addServerError = "" }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Name (optional)", "이름 (선택)")).font(.caption).foregroundStyle(.secondary)
                    TextField(L("My Server", "내 서버"), text: $addServerName)
                        .textFieldStyle(.roundedBorder)
                }

                if !addServerError.isEmpty {
                    Text(addServerError).font(.caption).foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    Button(L("Cancel", "취소")) { showAddServer = false }
                    Button(L("Add", "추가")) {
                        if let server = ServerStore.Server.from(offerURL: addServerURL, name: addServerName.isEmpty ? nil : addServerName) {
                            ServerStore.add(server)
                            Task { await model.connectToRemoteServer(server) }
                            showAddServer = false
                        } else {
                            addServerError = L("Invalid pairing link. Make sure it contains #offer=...", "유효하지 않은 페어링 링크입니다. #offer=...가 포함되어 있는지 확인하세요.")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(addServerURL.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func phone(_ status: Status?) -> some View {
        if let url = status?.phoneURL {
            HStack(alignment: .top, spacing: 18) {
                if let image = qrImage(url.absoluteString) {
                    Image(nsImage: image).interpolation(.none).resizable().frame(width: 180, height: 180)
                        .padding(8).background(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Connect your phone", "휴대폰 연결")).font(.headline)
                    Text(L("Open Ovis on your phone, tap Scan QR code, and point it here. Your phone needs Tailscale, signed in to the same account.",
                           "휴대폰에서 Ovis를 열고 Scan QR code를 눌러 이 화면을 찍으세요. 휴대폰에도 같은 계정으로 로그인한 Tailscale이 있어야 합니다."))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(url.absoluteString).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }
        } else if status?.tailscale == "running" {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Your phone needs an address for this Mac", "휴대폰이 열 주소가 아직 없습니다")).font(.headline)
                Text(L("Tailscale runs here: let it serve the app to your own devices.", "이 Mac에 Tailscale이 있습니다. 내 기기들에서만 열리는 주소를 만듭니다."))
                Button(L("Make the phone address", "휴대폰 주소 만들기")) { Task { await model.makePhoneAddress() } }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Your phone needs a way to reach this Mac", "휴대폰에서 이 Mac에 올 길이 필요합니다")).font(.headline)
                Text(status?.tailscale == "stopped"
                     ? L("Tailscale is installed but not signed in. Sign in to it, then check again.", "Tailscale이 설치돼 있지만 로그인되지 않았습니다. 로그인한 뒤 다시 확인해 주세요.")
                     : L("Install Tailscale on this Mac and on your phone, sign in to both with the same account, then check again.", "이 Mac과 휴대폰에 Tailscale을 설치하고 같은 계정으로 로그인한 뒤 다시 확인해 주세요."))
                    .fixedSize(horizontal: false, vertical: true)
                if status?.tailscale != "stopped" {
                    Button(L("Get Tailscale", "Tailscale 받기")) { model.open(Ovis.tailscaleDownload) }
                }
            }
        }
    }
}

func qrImage(_ text: String) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
    let rep = NSCIImageRep(ciImage: output)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

/// Handles APNs device token registration for push notifications
final class PushNotificationDelegate: NSObject, NSApplicationDelegate {
    static var tokenContinuation: CheckedContinuation<String?, Never>?

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushNotificationDelegate.tokenContinuation?.resume(returning: token)
        PushNotificationDelegate.tokenContinuation = nil
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationDelegate.tokenContinuation?.resume(returning: nil)
        PushNotificationDelegate.tokenContinuation = nil
    }
}
