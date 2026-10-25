import AppKit
import XCTest
@testable import TypingPet

@MainActor
final class InputMonitoringGuideTests: XCTestCase {
    func testWelcomeAndLocalPreviewDoNotRequestPermissionOrConnect() {
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
        XCTAssertTrue(model.hasTriedPreview)
        XCTAssertTrue(model.previewImage === reaction)
        XCTAssertFalse(model.receivedGlobalKeystroke())
        XCTAssertEqual(model.phase, .preview)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(connections, 0)
        XCTAssertEqual(settings, 0)
    }

    func testOnlyExplicitSetupRequestsPermissionAndPollingDoesNotRepeatIt() {
        var requests = 0
        var settings = 0
        let model = InputMonitoringGuideModel(
            isPermissionGranted: { false },
            connectMonitoring: { _ in XCTFail("Cannot connect without permission"); return false },
            requestPermission: { requests += 1 },
            openSettings: { settings += 1 }
        )

        model.beginSetup()
        model.beginSetup()
        model.refresh()
        model.refresh(restart: true)
        XCTAssertFalse(model.receivedGlobalKeystroke())
        XCTAssertEqual(model.phase, .permission)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(settings, 1)
        model.showSettings()
        XCTAssertEqual(settings, 2)
        XCTAssertEqual(requests, 1)
    }

    func testPermissionAndConnectionAreInsufficientUntilRealGlobalEvent() {
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
        XCTAssertEqual(model.phase, .connectionFailed)
        XCTAssertFalse(model.receivedGlobalKeystroke())

        connected = true
        model.refresh()
        XCTAssertEqual(model.phase, .verifying)
        model.previewKeystroke()
        XCTAssertEqual(model.phase, .verifying)
        XCTAssertFalse(model.hasTriedPreview)

        XCTAssertTrue(model.receivedGlobalKeystroke())
        XCTAssertEqual(model.phase, .complete)
        model.refresh()
        XCTAssertEqual(model.phase, .complete)
        XCTAssertFalse(model.receivedGlobalKeystroke(), "Completion should be reported only once")
    }

    func testAlreadyGrantedPermissionSkipsSystemSettingsAndRequest() {
        let model = InputMonitoringGuideModel(
            isPermissionGranted: { true },
            connectMonitoring: { _ in true },
            requestPermission: { XCTFail("Already authorized") },
            openSettings: { XCTFail("No settings visit needed") }
        )
        model.beginSetup()
        XCTAssertEqual(model.phase, .verifying)
        XCTAssertTrue(model.receivedGlobalKeystroke())
    }

    func testRelaunchResumesVerificationWithoutRequestingAgain() {
        var granted = false
        let model = InputMonitoringGuideModel(
            resumeSetup: true,
            isPermissionGranted: { granted },
            connectMonitoring: { _ in true },
            requestPermission: { XCTFail("Resuming must not request again") },
            openSettings: { XCTFail("Resuming must not steal focus") }
        )
        XCTAssertEqual(model.phase, .permission)
        model.refresh()
        XCTAssertEqual(model.phase, .permission)
        granted = true
        model.refresh()
        XCTAssertEqual(model.phase, .verifying)
        XCTAssertTrue(model.receivedGlobalKeystroke())
    }

    func testRevocationAndReconnectRequireVerificationAgain() {
        var granted = true
        var restartRequests: [Bool] = []
        let model = InputMonitoringGuideModel(
            isPermissionGranted: { granted },
            connectMonitoring: { restartRequests.append($0); return true },
            requestPermission: {},
            openSettings: {}
        )
        model.beginSetup()
        XCTAssertTrue(model.receivedGlobalKeystroke())
        model.refresh(restart: true)
        XCTAssertEqual(restartRequests.last, true)
        XCTAssertEqual(model.phase, .verifying)

        granted = false
        model.refresh()
        XCTAssertEqual(model.phase, .permission)
        XCTAssertFalse(model.receivedGlobalKeystroke())
        granted = true
        XCTAssertTrue(model.receivedGlobalKeystroke(), "A key can arrive before the permission poll")
        XCTAssertEqual(model.phase, .complete)
    }
}
