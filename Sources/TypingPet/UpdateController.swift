import AppKit
import Foundation

@MainActor
final class UpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateManifest)
        case downloading(UpdateManifest)
        case ready(StagedUpdate)
        case failed(String)
    }

    static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let automaticKey = "AutomaticUpdateChecks"
    private static let lastCheckKey = "LastUpdateCheck"
    private static let notifiedBuildKey = "NotifiedUpdateBuild"
    private static let pendingBuildKey = "PendingUpdateBuild"
    private static let pendingFolderKey = "PendingUpdateFolder"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var completedMessage: String?
    @Published var automaticChecks: Bool {
        didSet { defaults.set(automaticChecks, forKey: Self.automaticKey) }
    }
    let configuration: Result<UpdateConfiguration, UpdateError>
    var onChange: (() -> Void)?
    var isTimerRunning: () -> Bool = { false }

    private let defaults: UserDefaults
    private let session = UpdateInstaller.makeSession()
    private var timer: Timer?
    private var restartRequested = false

    init(defaults: UserDefaults = AppEnvironment.defaults, bundle: Bundle = .main) {
        self.defaults = defaults
        configuration = UpdateConfiguration.resolve(
            profile: AppEnvironment.profile,
            info: bundle.infoDictionary,
            feedOverride: defaults.string(forKey: UpdateConfiguration.feedOverrideKey)
        )
        automaticChecks = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        lastChecked = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    var currentVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "개발 실행"
        return (info?["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
    }

    var unavailableReason: String? {
        if case .failure(let error) = configuration { return error.localizedDescription }
        return nil
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading: return true
        default: return false
        }
    }

    var statusText: String {
        if let unavailableReason { return unavailableReason }
        switch phase {
        case .idle: return completedMessage ?? lastCheckedText
        case .checking: return "업데이트를 확인하는 중이에요…"
        case .upToDate: return "최신 버전이에요. \(lastCheckedText)"
        case .available(let manifest): return "새 버전 \(manifest.version)이 있어요."
        case .downloading(let manifest): return "\(manifest.version)을 내려받고 확인하는 중이에요…"
        case .ready(let staged): return "\(staged.manifest.version) 설치 준비가 끝났어요. 다시 시작하거나 종료할 때 설치돼요."
        case .failed(let message): return message
        }
    }

    var menuTitle: String {
        switch phase {
        case .checking: return "업데이트 확인 중…"
        case .available(let manifest): return "업데이트 설치 (\(manifest.version))"
        case .downloading: return "업데이트 내려받는 중…"
        case .ready(let staged): return "다시 시작해 업데이트 (\(staged.manifest.version))"
        default: return "업데이트 확인…"
        }
    }

    private var lastCheckedText: String {
        guard let lastChecked else { return "아직 확인하지 않았어요." }
        return "마지막 확인: \(lastChecked.formatted(date: .abbreviated, time: .shortened))"
    }

    func start() {
        reportPreviousInstall()
        guard unavailableReason == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
    }

    // One menu item walks through check, download, and restart.
    func performPrimaryAction() {
        switch phase {
        case .available: Task { await download() }
        case .ready: confirmRestart()
        case .checking, .downloading: break
        default: Task { await check(userInitiated: true) }
        }
    }

    func checkIfDue() {
        guard automaticChecks, !isBusy else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard case .success(let configuration) = configuration, !isBusy else {
            if userInitiated, let unavailableReason { alert("업데이트를 확인할 수 없어요", unavailableReason) }
            return
        }
        if case .ready = phase { return }
        setPhase(.checking)
        do {
            let manifest = try await UpdateInstaller.fetchManifest(configuration: configuration, session: session)
            lastChecked = Date()
            defaults.set(lastChecked, forKey: Self.lastCheckKey)
            guard manifest.isNewer(than: configuration.build) else {
                setPhase(.upToDate)
                if userInitiated { alert("최신 버전이에요", "\(AppEnvironment.displayName) \(configuration.version)을 사용하고 있어요.") }
                return
            }
            guard manifest.supports(ProcessInfo.processInfo.operatingSystemVersion) else {
                setPhase(.failed("\(manifest.version)은 macOS \(manifest.minimumSystemVersion) 이상이 필요해요."))
                return
            }
            setPhase(.available(manifest))
            let notified = defaults.integer(forKey: Self.notifiedBuildKey)
            if userInitiated || notified != manifest.build {
                defaults.set(manifest.build, forKey: Self.notifiedBuildKey)
                if offerInstall(manifest) { await download() }
            }
        } catch {
            setPhase(.failed(error.localizedDescription))
            if userInitiated { alert("업데이트를 확인하지 못했어요", error.localizedDescription) }
        }
    }

    func download() async {
        guard case .success(let configuration) = configuration, case .available(let manifest) = phase else { return }
        do {
            _ = try UpdateInstaller.installTarget(for: Bundle.main.bundleURL)
        } catch {
            setPhase(.failed(error.localizedDescription))
            alert("업데이트를 설치할 수 없어요", error.localizedDescription)
            return
        }
        setPhase(.downloading(manifest))
        do {
            let staged = try await UpdateInstaller.stage(manifest, configuration: configuration, session: session)
            setPhase(.ready(staged))
            confirmRestart()
        } catch {
            setPhase(.failed(error.localizedDescription))
            alert("업데이트를 설치하지 못했어요", error.localizedDescription)
        }
    }

    func restartToUpdate() {
        restartRequested = true
        NSApp.terminate(nil)
        restartRequested = false
    }

    // Called once termination is certain. A staged update installs even without a restart request.
    func applicationWillTerminate() {
        guard case .ready(let staged) = phase, case .success(let configuration) = configuration else { return }
        do {
            let target = try UpdateInstaller.installTarget(for: Bundle.main.bundleURL)
            try UpdateVerifier.verifyApp(at: staged.app, manifest: staged.manifest, configuration: configuration)
            try UpdateInstaller.launchHelper(for: staged, target: target, relaunch: restartRequested)
            defaults.set(staged.manifest.build, forKey: Self.pendingBuildKey)
            defaults.set(staged.folder.path, forKey: Self.pendingFolderKey)
        } catch {
            try? FileManager.default.removeItem(at: staged.folder)
        }
    }

    private func reportPreviousInstall() {
        defer {
            defaults.removeObject(forKey: Self.pendingBuildKey)
            defaults.removeObject(forKey: Self.pendingFolderKey)
            if case .success(let configuration) = configuration {
                try? FileManager.default.removeItem(at: UpdateInstaller.updatesFolder(bundleIdentifier: configuration.bundleIdentifier))
            }
        }
        let pending = defaults.integer(forKey: Self.pendingBuildKey)
        guard pending > 0, case .success(let configuration) = configuration else { return }
        if configuration.build >= pending {
            completedMessage = "\(configuration.version)으로 업데이트했어요."
        } else {
            let log = defaults.string(forKey: Self.pendingFolderKey)
                .flatMap { try? String(contentsOf: UpdateInstaller.logURL(in: URL(fileURLWithPath: $0)), encoding: .utf8) }
            let reason = log?.split(separator: "\n").last { $0.hasPrefix("FAILED") }.map(String.init) ?? "설치 기록이 없어요."
            setPhase(.failed("지난 업데이트를 설치하지 못했어요. \(reason)"))
        }
    }

    private func offerInstall(_ manifest: UpdateManifest) -> Bool {
        let notes = manifest.notes.map { "\n\n\($0)" } ?? ""
        let response = alert(
            "\(AppEnvironment.displayName) \(manifest.version)이 나왔어요",
            "지금 사용하는 버전은 \(currentVersionText)이에요.\(notes)",
            buttons: ["설치", "나중에"]
        )
        return response == .alertFirstButtonReturn
    }

    private func confirmRestart() {
        guard case .ready(let staged) = phase else { return }
        let timerNote = isTimerRunning() ? "\n\n실행 중인 타이머는 일시정지되고, 다시 열면 이어서 할 수 있어요." : ""
        let response = alert(
            "다시 시작해서 \(staged.manifest.version)으로 업데이트할까요?",
            "나중에를 고르면 앱을 종료할 때 설치돼요.\(timerNote)",
            buttons: ["다시 시작", "나중에"]
        )
        if response == .alertFirstButtonReturn { restartToUpdate() }
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        if phase != .idle { completedMessage = nil }
        onChange?()
    }

    @discardableResult
    private func alert(_ title: String, _ message: String, buttons: [String] = ["확인"]) -> NSApplication.ModalResponse {
        #if DEBUG
        if let automated = automatedResponse { return automated }
        #endif
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }

    #if DEBUG
    // `--install-update-now` accepts every prompt so scripts/check_update.sh can run unattended.
    private var automatedResponse: NSApplication.ModalResponse?

    func installNowForChecks() {
        automatedResponse = .alertFirstButtonReturn
        Task {
            await check(userInitiated: true)
            if case .ready = phase { return }
            FileHandle.standardError.write(Data("UPDATE CHECK FAILED: \(statusText)\n".utf8))
            exit(1)
        }
    }
    #endif
}
