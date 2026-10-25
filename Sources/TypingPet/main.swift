import AppKit

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let runLock = DevelopmentRunLock()
    if AppEnvironment.isDevelopment {
        do {
            guard try runLock.acquire(at: AppEnvironment.supportDirectory.appendingPathComponent(".runtime.lock")) else {
                let alert = NSAlert()
                alert.messageText = L("TypingPet Dev is already running")
                alert.informativeText = L("Use the DEV app in the menu bar. Quit the existing Dev app before launching again.")
                alert.runModal()
                exit(0)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Could not start TypingPet Dev")
            alert.informativeText = error.localizedDescription
            alert.runModal()
            exit(1)
        }
    }
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(runLock) { application.run() }
}
