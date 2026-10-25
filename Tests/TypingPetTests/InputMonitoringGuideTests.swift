import AppKit
import Testing
@testable import TypingPet

@Suite @MainActor
struct InputMonitoringGuideTests {
    @Test func welcomeAndLocalPreviewDoNotRequestPermissionOrConnect() {
        var requests = 0
        var connections = 0
        var settings = 0
        let idle = NSImage(size: NSSize(width: 1, height: 1))
        let reaction = NSImage(size: NSSize(width: 1, height: 1))
        let model = InputMonitoringGuideModel(
            idleImage: idle,
            reactionImages: [reaction],
            isPermissionGranted: { false },
            connectMonitoring: { _ in connections += 1; return false },
            requestPermission: { requests += 1 },
            openSettings: { settings += 1 }
        )

        model.refresh()
        model.previewKeystroke()
        #expect(model.hasTriedPreview)
        #expect(model.previewImage === reaction)
        #expect(!model.receivedGlobalKeystroke())
        #expect(model.phase == .preview)
        #expect(requests == 0)
        #expect(connections == 0)
        #expect(settings == 0)
    }

    @Test func onlyExplicitSetupRequestsPermissionAndPollingDoesNotRepeatIt() {
        var requests = 0
        var settings = 0
        let model = InputMonitoringGuideModel(
            isPermissionGranted: { false },
            connectMonitoring: { _ in Issue.record("Cannot connect without permission"); return false },
            requestPermission: { requests += 1 },
            openSettings: { settings += 1 }
        )

        model.beginSetup()
        model.beginSetup()
        model.refresh()
        model.refresh(restart: true)
        #expect(!model.receivedGlobalKeystroke())
        #expect(model.phase == .permission)
        #expect(requests == 1)
        #expect(settings == 1)
        model.showSettings()
        #expect(settings == 2)
        #expect(requests == 1)
    }

    @Test func permissionAndConnectionAreInsufficientUntilRealGlobalEvent() {
        var granted = false
        var connected = false
        let model = InputMonitoringGuideModel(
            isPermissionGranted: { granted },
            connectMonitoring: { _ in connected },
            requestPermission: {},
            openSettings: {}
        )

        model.beginSetup()
        granted = true
        model.refresh()
        #expect(model.phase == .connectionFailed)
        #expect(!model.receivedGlobalKeystroke())

        connected = true
        model.refresh()
        #expect(model.phase == .verifying)
        model.previewKeystroke()
        #expect(model.phase == .verifying)
        #expect(!model.hasTriedPreview)

        #expect(model.receivedGlobalKeystroke())
        #expect(model.phase == .complete)
        model.refresh()
        #expect(model.phase == .complete)
        #expect(!model.receivedGlobalKeystroke())
    }

    @Test func alreadyGrantedPermissionSkipsSystemSettingsAndRequest() {
        let model = InputMonitoringGuideModel(
            isPermissionGranted: { true },
            connectMonitoring: { _ in true },
            requestPermission: { Issue.record("Already authorized") },
            openSettings: { Issue.record("No settings visit needed") }
        )
        model.beginSetup()
        #expect(model.phase == .verifying)
        #expect(model.receivedGlobalKeystroke())
    }

    @Test func relaunchResumesVerificationWithoutRequestingAgain() {
        var granted = false
        let model = InputMonitoringGuideModel(
            resumeSetup: true,
            isPermissionGranted: { granted },
            connectMonitoring: { _ in true },
            requestPermission: { Issue.record("Resuming must not request again") },
            openSettings: { Issue.record("Resuming must not steal focus") }
        )
        #expect(model.phase == .permission)
        model.refresh()
        #expect(model.phase == .permission)
        granted = true
        model.refresh()
        #expect(model.phase == .verifying)
        #expect(model.receivedGlobalKeystroke())
    }

    @Test func revocationAndReconnectRequireVerificationAgain() {
        var granted = true
        var restartRequests: [Bool] = []
        let model = InputMonitoringGuideModel(
            isPermissionGranted: { granted },
            connectMonitoring: { restartRequests.append($0); return true },
            requestPermission: {},
            openSettings: {}
        )
        model.beginSetup()
        #expect(model.receivedGlobalKeystroke())
        model.refresh(restart: true)
        #expect(restartRequests.last == true)
        #expect(model.phase == .verifying)

        granted = false
        model.refresh()
        #expect(model.phase == .permission)
        #expect(!model.receivedGlobalKeystroke())
        granted = true
        #expect(model.receivedGlobalKeystroke())
        #expect(model.phase == .complete)
    }
}
