import CoreGraphics
import Foundation
import Testing
@testable import TypingPet

@Suite struct PetWindowGeometryTests {
    @Test func inputMonitoringGuideConvertsQuartzWindowCoordinates() {
        let frame = InputMonitoringGuidePlacement.appKitFrame(
            fromQuartzFrame: CGRect(x: 120, y: 180, width: 740, height: 522),
            primaryScreenMaxY: 1_440
        )

        #expect(frame == CGRect(x: 120, y: 738, width: 740, height: 522))
    }

    @Test func inputMonitoringGuidePrefersRightSideOfSettingsWindow() {
        let origin = InputMonitoringGuidePlacement.origin(
            panelSize: CGSize(width: 404, height: 336),
            beside: CGRect(x: 400, y: 300, width: 740, height: 522),
            in: CGRect(x: 0, y: 40, width: 1_800, height: 1_060)
        )

        #expect(origin == CGPoint(x: 1_152, y: 486))
    }

    @Test func inputMonitoringGuideUsesLeftSideWhenRightSideIsTooNarrow() {
        let origin = InputMonitoringGuidePlacement.origin(
            panelSize: CGSize(width: 404, height: 336),
            beside: CGRect(x: 1_458, y: 766, width: 740, height: 522),
            in: CGRect(x: 0, y: 87, width: 2_560, height: 1_323)
        )

        #expect(origin == CGPoint(x: 1_042, y: 952))
    }

    @Test func inputMonitoringGuideStaysInsideVisibleFrameWhenBothSidesAreNarrow() {
        let origin = InputMonitoringGuidePlacement.origin(
            panelSize: CGSize(width: 404, height: 336),
            beside: CGRect(x: 260, y: 220, width: 920, height: 650),
            in: CGRect(x: 0, y: 40, width: 1_440, height: 860)
        )

        #expect(origin == CGPoint(x: 1_024, y: 534))
    }

    @Test func detectsApplicationsFolderLocationsForPermissionGuide() {
        #expect(
            TypingPetAppLocation.detect(
                appURL: URL(fileURLWithPath: "/Applications/TypingPet.app"),
                homeDirectory: URL(fileURLWithPath: "/Users/test")
            ) == .applications
        )
        #expect(
            TypingPetAppLocation.detect(
                appURL: URL(fileURLWithPath: "/Users/test/Applications/TypingPet.app"),
                homeDirectory: URL(fileURLWithPath: "/Users/test")
            ) == .applications
        )
    }

    @Test func detectsUnsafePermissionGuideLocations() {
        #expect(
            TypingPetAppLocation.detect(
                appURL: URL(fileURLWithPath: "/Users/test/Downloads/TypingPet.app"),
                homeDirectory: URL(fileURLWithPath: "/Users/test")
            ) == .outsideApplications
        )
        #expect(
            TypingPetAppLocation.detect(
                appURL: URL(fileURLWithPath: "/private/var/folders/AppTranslocation/TypingPet.app"),
                homeDirectory: URL(fileURLWithPath: "/Users/test")
            ) == .translocated
        )
    }

    @Test func pointerAvoidanceMovesAwayFromNearbyPointer() throws {
        let frame = CGRect(x: 100, y: 100, width: 100, height: 100)
        let mouse = CGPoint(x: 80, y: 150)
        let target = try #require(PetPointerAvoidance.targetOrigin(
            mouseLocation: mouse,
            petFrame: frame,
            bounds: CGRect(x: 0, y: 0, width: 500, height: 500)
        ))

        #expect(target.x > frame.origin.x)
        #expect(
            PetPointerAvoidance.distance(from: mouse, to: CGRect(origin: target, size: frame.size)) >
            PetPointerAvoidance.distance(from: mouse, to: frame)
        )
    }

    @Test func pointerAvoidanceCanChooseDiagonalEscapeForHorizontalApproach() throws {
        let frame = CGRect(x: 180, y: 180, width: 100, height: 100)
        let target = try #require(PetPointerAvoidance.targetOrigin(
            mouseLocation: CGPoint(x: 160, y: 230),
            petFrame: frame,
            bounds: CGRect(x: 0, y: 0, width: 500, height: 500)
        ))

        #expect(target.x > frame.origin.x)
        #expect(abs(target.y - frame.origin.y) > 0.001)
    }

    @Test func pointerAvoidanceDoesNothingWhenPointerIsFarAway() {
        #expect(PetPointerAvoidance.targetOrigin(
            mouseLocation: CGPoint(x: 0, y: 0),
            petFrame: CGRect(x: 300, y: 300, width: 100, height: 100),
            bounds: CGRect(x: 0, y: 0, width: 500, height: 500)
        ) == nil)
    }

    @Test func pointerAvoidanceChoosesAnAvailableDirectionAtScreenEdge() throws {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
        let frame = CGRect(x: 0, y: 180, width: 100, height: 100)
        let target = try #require(PetPointerAvoidance.targetOrigin(
            mouseLocation: CGPoint(x: 60, y: 230),
            petFrame: frame,
            bounds: bounds
        ))

        #expect(target != frame.origin)
        #expect(target.x >= bounds.minX)
        #expect(target.y >= bounds.minY)
        #expect(target.x + frame.width <= bounds.maxX)
        #expect(target.y + frame.height <= bounds.maxY)
    }

    @Test func pointerAvoidanceReturnsNilWhenPinnedInCornerCannotMoveFurther() {
        let tightBounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let mouse = CGPoint(x: 50, y: 50)
        let target = PetPointerAvoidance.targetOrigin(
            mouseLocation: mouse,
            petFrame: frame,
            bounds: tightBounds
        )
        #expect(target == nil)
    }

    @Test func opacitySelectsRestingAndHoverValuesImmediately() {
        #expect(
            abs(PetOpacityBehavior.opacity(
                isHovering: false,
                restingOpacity: 1,
                hoverOpacity: 0.3
            ) - 1.0) < 0.0001
        )
        #expect(
            abs(PetOpacityBehavior.opacity(
                isHovering: true,
                restingOpacity: 1,
                hoverOpacity: 0.3
            ) - 0.3) < 0.0001
        )
    }

    @Test func opacityValuesAreClampedToValidRange() {
        #expect(
            abs(PetOpacityBehavior.opacity(
                isHovering: false,
                restingOpacity: 1.4,
                hoverOpacity: 0.3
            ) - 1.0) < 0.0001
        )
        #expect(
            abs(PetOpacityBehavior.opacity(
                isHovering: true,
                restingOpacity: 1,
                hoverOpacity: -0.2
            ) - 0.0) < 0.0001
        )
    }

    @Test func releaseVelocityUsesRecentPointerMovement() {
        let velocity = PetMotionPhysics.releaseVelocity(samples: [
            PetDragSample(point: CGPoint(x: 0, y: 0), timestamp: 1.0),
            PetDragSample(point: CGPoint(x: 10, y: 5), timestamp: 1.1),
            PetDragSample(point: CGPoint(x: 40, y: 20), timestamp: 1.2),
        ])

        #expect(abs(velocity.dx - 300) < 0.001)
        #expect(abs(velocity.dy - 150) < 0.001)
    }

    @Test func releaseVelocityIsCapped() {
        let velocity = PetMotionPhysics.releaseVelocity(samples: [
            PetDragSample(point: .zero, timestamp: 1),
            PetDragSample(point: CGPoint(x: 1_000, y: 0), timestamp: 1.01),
        ])

        #expect(abs(hypot(velocity.dx, velocity.dy) - 900) < 0.001)
    }

    @Test func motionDecaysAndStaysInsideVisibleBounds() {
        let freeStep = PetMotionPhysics.advance(
            origin: CGPoint(x: 100, y: 100),
            size: CGSize(width: 100, height: 100),
            velocity: CGVector(dx: 600, dy: 300),
            elapsed: 0.1,
            bounds: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        #expect(abs(freeStep.origin.x - 160) < 0.001)
        #expect(abs(freeStep.origin.y - 130) < 0.001)
        #expect(freeStep.velocity.dx < 600)

        let edgeStep = PetMotionPhysics.advance(
            origin: CGPoint(x: 390, y: 100),
            size: CGSize(width: 100, height: 100),
            velocity: CGVector(dx: 600, dy: 0),
            elapsed: 0.1,
            bounds: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        #expect(abs(edgeStep.origin.x - 400) < 0.001)
        #expect(edgeStep.velocity.dx < 0)
    }

    @Test func horizontalResizeUsesWidthAndPreservesScaleRelationship() {
        let scale = PetResizeGeometry.scale(
            initialScale: 0.5,
            initialSize: CGSize(width: 200, height: 100),
            dragDelta: CGPoint(x: 100, y: 0)
        )
        #expect(abs(scale - 0.75) < 0.0001)
    }

    @Test func verticalResizeUsesHeight() {
        let scale = PetResizeGeometry.scale(
            initialScale: 0.5,
            initialSize: CGSize(width: 200, height: 100),
            dragDelta: CGPoint(x: 0, y: 50)
        )
        #expect(abs(scale - 0.75) < 0.0001)
    }

    @Test func resizeClampsToSupportedRange() {
        #expect(
            abs(PetResizeGeometry.scale(
                initialScale: 0.5,
                initialSize: CGSize(width: 200, height: 100),
                dragDelta: CGPoint(x: -500, y: 0)
            ) - 0.35) < 0.0001
        )
        #expect(
            abs(PetResizeGeometry.scale(
                initialScale: 1,
                initialSize: CGSize(width: 200, height: 100),
                dragDelta: CGPoint(x: 500, y: 0)
            ) - 1.25) < 0.0001
        )
    }

    @Test func bounceAmplitudesCoverEveryShakeLevel() {
        let levels = AppPreferencesDefault.minShakeLevel...AppPreferencesDefault.maxShakeLevel
        #expect(levels.allSatisfy { PetConstants.bounceAmplitudes.indices.contains($0) })
        #expect(PetConstants.bounceAmplitudes[AppPreferencesDefault.minShakeLevel] == 0)
    }
}
