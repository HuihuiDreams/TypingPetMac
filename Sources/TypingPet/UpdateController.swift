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
    private static let automaticKey = AppPreferencesKey.automaticUpdateChecks
    private static let lastCheckKey = AppPreferencesKey.lastUpdateCheck
    private static let notifiedBuildKey = AppPreferencesKey.notifiedUpdateBuild
    private static let pendingBuildKey = AppPreferencesKey.pendingUpdateBuild
    private static let pendingFolderKey = AppPreferencesKey.pendingUpdateFolder

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var completedMessage: String?
    @Published var automaticChecks: Bool {
        didSet { defaults.set(automaticChecks, forKey: Self.automaticKey) }
    }
    private let bundle: Bundle
    var configuration: Result<UpdateConfiguration, UpdateError> {
        UpdateConfiguration.resolve(
            profile: AppEnvironment.profile,
            info: bundle.infoDictionary,
            feedOverride: defaults.string(forKey: UpdateConfiguration.feedOverrideKey)
        )
    }
    var onChange: (() -> Void)?
    var isTimerRunning: () -> Bool = { false }

    private let defaults: UserDefaults
    private let session = UpdateInstaller.makeSession()
    private var timer: Timer?
    private var restartRequested = false

    init(defaults: UserDefaults = AppEnvironment.defaults, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
        automaticChecks = defaults.object(forKey: Self.automaticKey) as? Bool ?? AppPreferencesDefault.automaticUpdateChecks
        lastChecked = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    var currentVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? L("Development build")
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
        case .checking: return L("Checking for updates…")
        case .upToDate: return L("You are up to date. %1$@", lastCheckedText)
        case .available(let manifest): return L("Version %1$@ is available.", manifest.version)
        case .downloading(let manifest): return L("Downloading and verifying %1$@…", manifest.version)
        case .ready(let staged): return L("%1$@ is ready. It will be installed when you restart or quit.", staged.manifest.version)
        case .failed(let message): return message
        }
    }

    var menuTitle: String {
        switch phase {
        case .checking: return L("Checking for Updates…")
        case .available(let manifest): return L("Install Update (%1$@)", manifest.version)
        case .downloading: return L("Downloading Update…")
        case .ready(let staged): return L("Restart to Update (%1$@)", staged.manifest.version)
        default: return L("Check for Updates…")
        }
    }

    private var lastCheckedText: String {
        guard let lastChecked else { return L("No checks yet.") }
        return L("Last checked: %1$@", lastChecked.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocalization.shared.locale)
        ))
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
            if userInitiated, let unavailableReason { alert(L("Cannot check for updates"), unavailableReason) }
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
                if userInitiated { alert(L("You are up to date"), L("You are using %1$@ %2$@.", AppEnvironment.displayName, configuration.version)) }
                return
            }
            guard manifest.supports(ProcessInfo.processInfo.operatingSystemVersion) else {
                setPhase(.failed(L("%1$@ requires macOS %2$@ or later.", manifest.version, manifest.minimumSystemVersion)))
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
            if userInitiated { alert(L("Could not check for updates"), error.localizedDescription) }
        }
    }

    func download() async {
        guard case .success(let configuration) = configuration, case .available(let manifest) = phase else { return }
        do {
            _ = try UpdateInstaller.installTarget(for: Bundle.main.bundleURL)
        } catch {
            setPhase(.failed(error.localizedDescription))
            alert(L("Cannot install update"), error.localizedDescription)
            return
        }
        setPhase(.downloading(manifest))
        do {
            let staged = try await UpdateInstaller.stage(manifest, configuration: configuration, session: session)
            setPhase(.ready(staged))
            confirmRestart()
        } catch {
            setPhase(.failed(error.localizedDescription))
            alert(L("Could not install update"), error.localizedDescription)
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
            completedMessage = L("Updated to %1$@.", configuration.version)
        } else {
            let log = defaults.string(forKey: Self.pendingFolderKey)
                .flatMap { try? String(contentsOf: UpdateInstaller.logURL(in: URL(fileURLWithPath: $0)), encoding: .utf8) }
            let reason = log?.split(separator: "\n").last { $0.hasPrefix("FAILED") }.map(String.init) ?? L("No installation record.")
            setPhase(.failed(L("The previous update could not be installed. %1$@", reason)))
        }
    }

    private func offerInstall(_ manifest: UpdateManifest) -> Bool {
        let notes = manifest.notes.map { "\n\n\($0)" } ?? ""
        let response = alert(
            L("%1$@ %2$@ is available", AppEnvironment.displayName, manifest.version),
            L("You are currently using %1$@.%2$@", currentVersionText, notes),
            buttons: [L("Install"), L("Later")]
        )
        return response == .alertFirstButtonReturn
    }

    private func confirmRestart() {
        guard case .ready(let staged) = phase else { return }
        let timerNote = isTimerRunning() ? L("\n\nThe running timer will pause. You can resume it after reopening.") : ""
        let response = alert(
            L("Restart to update to %1$@?", staged.manifest.version),
            L("Choose Later to install when you quit the app.%1$@", timerNote),
            buttons: [L("Restart"), L("Later")]
        )
        if response == .alertFirstButtonReturn { restartToUpdate() }
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        if phase != .idle { completedMessage = nil }
        onChange?()
    }

    @discardableResult
    private func alert(_ title: String, _ message: String, buttons: [String] = [L("OK")]) -> NSApplication.ModalResponse {
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
