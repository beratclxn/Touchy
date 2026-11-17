import AppKit
import CoreGraphics

struct TouchPoint {
    let id: Int
    let p: CGPoint
    let size: Double
    let isStylus: Bool

    init(id: Int, p: CGPoint, size: Double = 0.0, isStylus: Bool = false) {
        self.id = id
        self.p = p
        self.size = size
        self.isStylus = isStylus
    }
}

/// Multi-touch gesture state machine with multi-layer Palm Rejection for universal capacitive and active styluses.
final class GestureEngine {
    private let injector: EventInjector

    private enum Thresholds {
        static let dragStartDistance: CGFloat = 9.0
        static let tapMoveTolerance: CGFloat = 14.0
        static let longPressMoveTolerance: CGFloat = 8.0
        static let longPressDelay: TimeInterval = 0.95
        static let twoFingerTapMaxDuration: TimeInterval = 0.32
        static let minTwoFingerSeparation: CGFloat = 62.0
        static let splitContactMergeDistance: CGFloat = 44.0
        static let palmClusterRadius: CGFloat = 95.0
        static let palmVerticalSeparation: CGFloat = 75.0
        static let palmTotalSeparation: CGFloat = 140.0
        static let stationaryPalmMaxMove: CGFloat = 5.0
        static let movingStylusMinMove: CGFloat = 20.0
        static let activeStylusCooldown: TimeInterval = 0.40
        static let scrollStartDistance: CGFloat = 9.0
        static let pinchStartRatio: CGFloat = 0.08
        static let rotateStartDegrees: CGFloat = 2.8
        static let horizontalNavDistance: CGFloat = 52.0
        static let horizontalSwipeGain: Double = 2.2
        static let swipeCommitDistance: CGFloat = 70.0
        static let minMomentumSpeed: CGFloat = 140.0
        static let maxMomentumSpeed: CGFloat = 6000.0
        static let stopMomentumSpeed: CGFloat = 30.0
        static let momentumDecay: CGFloat = 0.95
        static let momentumFrameInterval: TimeInterval = 1.0 / 60.0
        static let bottomEdgeDockZoneHeight: CGFloat = 85.0
        static let bottomEdgeSwipeUpDistance: CGFloat = 12.0
    }

    private enum Mode {
        case idle
        case pending
        case dragging
        case trafficLights
        case multiPending
        case scrolling
        case pinchRotate
        case swipe
        case dockSwipeUp
        case waitLift
    }

    private var mode: Mode = .idle
    private var primaryID = 0
    private var startPoint = CGPoint.zero
    private var lastPoint = CGPoint.zero
    private var startTime: TimeInterval = 0
    private var longPressWorkItem: DispatchWorkItem?
    private var tapReleaseWatchdogWorkItem: DispatchWorkItem?
    private var pendingTouchFrames = 0
    private var lastPendingTouchTime: TimeInterval = 0
    private var multiEnteredFromSingle = false
    private var pendingMultiConfirmFrames = 0
    private var lastStylusTime: TimeInterval = -10.0

    private var trackedIDs: Set<Int> = []
    private var multiStartPositions: [Int: CGPoint] = [:]
    private var multiStartCentroid = CGPoint.zero
    private var lastCentroid = CGPoint.zero
    private var multiStartDistance: CGFloat = 1.0
    private var lastDistance: CGFloat = 1.0
    private var multiStartAngle: CGFloat = 0.0
    private var lastAngle: CGFloat = 0.0
    private var magnifyBegan = false
    private var rotateBegan = false
    private var isHorizontalScroll = false
    private var maxCentroidDrift: CGFloat = 0.0
    private var multiValidFrames = 0
    private var multiLifting = false
    private var maxFingers = 0

    private var scrollVelocity = CGVector.zero
    private var peakScrollVelocity = CGVector.zero
    private var peakVelocityTime: TimeInterval = 0
    private var lastScrollTime: TimeInterval = 0
    private var momentumTimer: Timer?
    private var momentumStarted = false

    init(injector: EventInjector) {
        self.injector = injector
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - Frame Processing

    func process(_ rawTouches: [TouchPoint]) {
        let coalesced = Self.coalesceSplitContacts(rawTouches)

        // When the iPadOS Touch Keyboard is visible and any finger is touching inside the keyboard,
        // isolate the keyboard touch and ignore any resting palm contacts outside the keyboard!
        if TouchKeyboardController.shared.isVisible {
            let kbTouches = coalesced.filter { TouchKeyboardController.shared.contains($0.p) }
            if !kbTouches.isEmpty {
                stopMomentum()
                let activeKB = kbTouches.first(where: { $0.id == primaryID }) ?? kbTouches.last!
                if mode != .idle && !TouchKeyboardController.shared.contains(startPoint) {
                    // We were tracking a resting palm outside the keyboard; switch cleanly to the key tap inside the keyboard.
                    cancelLongPress()
                    if mode == .dragging {
                        injector.mouseUp(at: lastPoint)
                        WindowSnapController.shared.cancelDrag()
                    }
                    mode = .idle
                }
                if mode == .idle || mode == .multiPending || mode == .waitLift {
                    beginSingle(activeKB)
                } else if mode == .dragging {
                    // Dragging the keyboard by its top handle (or any key-area drag) keeps streaming drag events.
                    handleDragging([activeKB])
                } else {
                    handlePending([activeKB])
                }
                return
            }
        }

        let touches = Settings.shared.palmRejection ? filterPalmContacts(coalesced) : coalesced

        if !touches.isEmpty { stopMomentum() }
        maxFingers = max(maxFingers, touches.count)

        switch mode {
        case .idle:
            guard !touches.isEmpty else { return }
            maxFingers = touches.count
            touches.count == 1 ? beginSingle(touches[0]) : beginMulti(touches)
        case .pending:
            handlePending(touches)
        case .dragging:
            handleDragging(touches)
        case .trafficLights:
            handleTrafficLights(touches)
        case .multiPending:
            handleMultiPending(touches)
        case .scrolling:
            handleScrolling(touches)
        case .pinchRotate:
            handlePinchRotate(touches)
        case .swipe:
            handleSwipe(touches)
        case .dockSwipeUp:
            if touches.isEmpty {
                // Restart the bottom-edge Dock reveal now that all fingers have lifted off the glass,
                // guaranteeing zero raw HID touch packets interfere with WindowServer's bottom-edge dwell timer.
                let bounds = Self.displayBounds(for: startPoint)
                injector.revealDock(at: startPoint, displayBounds: bounds)
                mode = .idle
            }
        case .waitLift:
            if touches.isEmpty { mode = .idle }
        }
    }

    func reset() {
        cancelLongPress()
        stopMomentum()
        TrafficLightOverlayController.shared.dismiss()
        WindowSnapController.shared.cancelDrag()
        switch mode {
        case .dragging:    injector.mouseUp(at: lastPoint)
        case .scrolling:   injector.scroll(dx: 0, dy: 0, at: lastCentroid, phase: .ended)
        case .pinchRotate: endPinchRotate(at: lastCentroid)
        default:           break
        }
        mode = .idle
    }

    // MARK: - Universal Stylus & Palm Rejection Pipeline

    /// Filters resting palm contacts while preserving both universal stylus drawing and intentional 2-finger gestures.
    private func filterPalmContacts(_ touches: [TouchPoint]) -> [TouchPoint] {
        guard !touches.isEmpty else { return [] }

        // 1. Hardware Active Stylus Priority: if an active HID pen/stylus is present, ignore all hand/palm touches.
        let stylusContacts = touches.filter { $0.isStylus }
        if !stylusContacts.isEmpty {
            lastStylusTime = now
            return [stylusContacts[0]]
        }
        if (now - lastStylusTime) < Thresholds.activeStylusCooldown {
            return []
        }

        // 2. Active Stroke Lock: once a single-point drawing/dragging stroke has begun (`mode == .dragging`),
        // lock onto the primary stylus contact and ignore any resting palm contacts that touch down mid-stroke.
        if mode == .dragging, touches.count >= 2 {
            if let locked = touches.first(where: { $0.id == primaryID }) {
                return [locked]
            }
            if let nearest = touches.min(by: { Self.distance($0.p, lastPoint) < Self.distance($1.p, lastPoint) }),
               Self.distance(nearest.p, lastPoint) < 70.0 {
                return [nearest]
            }
        }

        guard touches.count >= 2, mode != .scrolling, mode != .pinchRotate, mode != .swipe else {
            return touches
        }

        // 3. Relative Contact Area Rejection (when digitizer reports Width/Height 0x48/0x49):
        // If one contact is a fine stylus tip and others have > 3.0× its contact diameter (and > 35% sensor width), strip the large palm contacts.
        var candidates = touches
        let positiveSizes = candidates.map { $0.size }.filter { $0 > 0.001 }
        if let minSize = positiveSizes.min(), positiveSizes.count >= 2 {
            let sizeCutoff = max(0.35, minSize * 3.0)
            let fineContacts = candidates.filter { $0.size <= sizeCutoff }
            if !fineContacts.isEmpty && fineContacts.count < candidates.count {
                candidates = fineContacts
                if candidates.count == 1 { return candidates }
            }
        }

        // 4. Palm Heel Cluster Rejection for Universal Capacitive Styluses:
        // When 2+ lower contacts form a tight palm heel cluster (< 95pt apart) while the stylus tip (`topContact`)
        // is isolated higher up on the screen (> 140pt away), isolate the stylus tip.
        if candidates.count >= 3, let topContact = candidates.min(by: { $0.p.y < $1.p.y }) {
            let others = candidates.filter { $0.id != topContact.id }
            if others.count >= 2 {
                let clusterSpan = Self.span(others)
                let minDistToTop = others.map { Self.distance($0.p, topContact.p) }.min() ?? 0
                if clusterSpan < Thresholds.palmClusterRadius && minDistToTop > Thresholds.palmTotalSeparation && (others[0].p.y - topContact.p.y) > 50.0 {
                    return [topContact]
                }
            }
        }

        return candidates
    }

    // MARK: - Single-Finger / Stylus Handlers

    private func beginSingle(_ touch: TouchPoint) {
        injector.cancelDockReveal()
        TouchKeyboardController.shared.handleTouchDown(at: touch.p)

        if TrafficLightOverlayController.shared.isVisible {
            if TrafficLightOverlayController.shared.contains(touch.p) {
                mode = .trafficLights
                primaryID = touch.id
                startPoint = touch.p
                lastPoint = touch.p
                TrafficLightOverlayController.shared.updateTouchPoint(touch.p)
                return
            } else {
                TrafficLightOverlayController.shared.dismiss()
            }
        }

        mode = .pending
        primaryID = touch.id
        startPoint = touch.p
        lastPoint = touch.p
        startTime = now
        pendingTouchFrames = 1
        lastPendingTouchTime = now
        multiEnteredFromSingle = false
        pendingMultiConfirmFrames = 0
        injector.move(to: touch.p)
        scheduleTapReleaseWatchdog()

        guard Settings.shared.longPressRightClick else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.mode == .pending,
                  Self.distance(self.lastPoint, self.startPoint) <= Thresholds.longPressMoveTolerance else { return }
            // Verify that the finger has been continuously streaming HID frames right up to the long-press deadline.
            // If the finger already lifted off (and its lift-off HID packet was missed), execute a normal left click instead.
            guard self.pendingTouchFrames >= 18,
                  (self.now - self.lastPendingTouchTime) < 0.16 else {
                self.cancelLongPress()
                self.mode = .idle
                if self.pendingTouchFrames <= 14 {
                    self.completeSingleTap(at: self.startPoint)
                }
                return
            }
            self.cancelTapReleaseWatchdog()
            self.injector.rightClick(at: self.startPoint)
            self.mode = .waitLift
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Thresholds.longPressDelay, execute: work)
    }

    private func completeSingleTap(at point: CGPoint) {
        if TrafficLightOverlayController.shared.tryExpand(at: point, injector: injector) {
            TouchKeyboardController.shared.dismiss()
            return
        }
        let tappedInsideKeyboard = TouchKeyboardController.shared.contains(point)
        injector.click(at: point)
        if !tappedInsideKeyboard {
            TouchKeyboardController.shared.handleScreenTap(at: point, injector: injector)
        }
    }

    private func scheduleTapReleaseWatchdog() {
        tapReleaseWatchdogWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .pending else { return }
            if self.pendingTouchFrames <= 12,
               Self.distance(self.lastPoint, self.startPoint) <= Thresholds.tapMoveTolerance {
                self.cancelLongPress()
                self.mode = .idle
                self.completeSingleTap(at: self.startPoint)
            }
        }
        tapReleaseWatchdogWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.115, execute: work)
    }

    private func cancelTapReleaseWatchdog() {
        tapReleaseWatchdogWorkItem?.cancel()
        tapReleaseWatchdogWorkItem = nil
    }

    private func handleTrafficLights(_ touches: [TouchPoint]) {
        if touches.isEmpty {
            mode = .idle
            TrafficLightOverlayController.shared.commitTouchRelease(at: lastPoint)
            return
        }
        if let activeTouch = touches.first(where: { $0.id == primaryID }) ?? touches.first {
            primaryID = activeTouch.id
            lastPoint = activeTouch.p
            TrafficLightOverlayController.shared.updateTouchPoint(activeTouch.p)
        }
    }

    private func handlePending(_ touches: [TouchPoint]) {
        if touches.isEmpty {
            cancelLongPress()
            mode = .idle
            completeSingleTap(at: startPoint)
            return
        }
        if touches.count >= 2 {
            // Only lock to single-point stylus dragging if the primary contact has already been drawing alone
            // AND the newly added contact is in a lower palm-heel geometry (> 135pt away and > 75pt lower).
            // Never hijack fast two-finger swipes or two-finger rotations where one finger lands 1 frame early!
            if Settings.shared.palmRejection,
               (now - startTime) > 0.08,
               let primary = touches.first(where: { $0.id == primaryID }),
               let other = touches.first(where: { $0.id != primaryID }),
               Self.distance(primary.p, startPoint) > 22.0,
               (other.p.y - primary.p.y) > Thresholds.palmVerticalSeparation,
               Self.distance(other.p, primary.p) > Thresholds.palmTotalSeparation {
                cancelLongPress()
                TouchKeyboardController.shared.handleOutsideGestureBegan(at: startPoint)
                WindowSnapController.shared.beginDrag(at: startPoint)
                injector.mouseDown(at: startPoint)
                injector.drag(to: primary.p)
                WindowSnapController.shared.updateDrag(at: primary.p)
                lastPoint = primary.p
                mode = .dragging
                return
            }

            if Self.span(touches) >= Thresholds.minTwoFingerSeparation {
                cancelLongPress()
                multiEnteredFromSingle = true
                beginMulti(touches)
            }
            return
        }
        pendingMultiConfirmFrames = 0
        let activeTouch: TouchPoint
        if let sameFinger = touches.first(where: { $0.id == primaryID }) {
            activeTouch = sameFinger
        } else if Self.distance(touches[0].p, lastPoint) < 35.0 {
            activeTouch = touches[0]
        } else {
            // The original tapping finger (primaryID) lifted off while a distant resting contact remained on screen.
            cancelLongPress()
            completeSingleTap(at: startPoint)
            mode = .waitLift
            return
        }
        primaryID = activeTouch.id
        lastPoint = activeTouch.p
        pendingTouchFrames += 1
        lastPendingTouchTime = now
        scheduleTapReleaseWatchdog()

        // Bottom-Edge Swipe-Up to Reveal macOS Dock:
        // When a touch begins near the bottom edge of the display and pulls slightly upward, summon the Dock.
        let displayBounds = Self.displayBounds(for: startPoint)
        let dx = activeTouch.p.x - startPoint.x
        let dy = activeTouch.p.y - startPoint.y
        if displayBounds.height > 0,
           startPoint.y >= (displayBounds.maxY - Thresholds.bottomEdgeDockZoneHeight),
           dy < 0,
           abs(dx) <= abs(dy) * 1.6 {
            if dy <= -Thresholds.bottomEdgeSwipeUpDistance {
                cancelLongPress()
                TouchKeyboardController.shared.dismiss()
                injector.revealDock(at: startPoint, displayBounds: displayBounds)
                mode = .dockSwipeUp
            }
            return
        }

        if Self.distance(activeTouch.p, startPoint) > Thresholds.dragStartDistance {
            cancelLongPress()
            TouchKeyboardController.shared.handleOutsideGestureBegan(at: startPoint)
            WindowSnapController.shared.beginDrag(at: startPoint)
            injector.mouseDown(at: startPoint)
            injector.drag(to: activeTouch.p)
            WindowSnapController.shared.updateDrag(at: activeTouch.p)
            mode = .dragging
        }
    }

    private func handleDragging(_ touches: [TouchPoint]) {
        guard let activeTouch = touches.first(where: { $0.id == primaryID }) ?? (touches.count == 1 ? touches.first : nil) else {
            injector.mouseUp(at: lastPoint)
            WindowSnapController.shared.endDrag(at: lastPoint)
            mode = touches.isEmpty ? .idle : .waitLift
            return
        }
        primaryID = activeTouch.id
        if activeTouch.p != lastPoint {
            injector.drag(to: activeTouch.p)
            WindowSnapController.shared.updateDrag(at: activeTouch.p)
            lastPoint = activeTouch.p
        }
    }

    private func cancelLongPress() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        cancelTapReleaseWatchdog()
    }

    // MARK: - Multi-Finger Handlers

    private func beginMulti(_ touches: [TouchPoint]) {
        injector.cancelDockReveal()
        TrafficLightOverlayController.shared.dismiss()
        trackedIDs = Set(touches.lazy.map { $0.id })
        multiStartPositions.removeAll(keepingCapacity: true)
        for touch in touches {
            multiStartPositions[touch.id] = touch.p
        }
        multiStartCentroid = Self.centroid(touches)
        lastCentroid = multiStartCentroid
        multiStartDistance = max(Self.span(touches), 1.0)
        lastDistance = multiStartDistance
        multiStartAngle = Self.angle(touches)
        lastAngle = multiStartAngle
        magnifyBegan = false
        rotateBegan = false
        isHorizontalScroll = false
        maxCentroidDrift = 0.0
        multiValidFrames = 1
        multiLifting = false
        startTime = now

        // Move the pointer to the two-finger centroid immediately so the target window/view under the fingers
        // receives all subsequent scroll, swipe, magnify, and rotate events.
        injector.move(to: multiStartCentroid)

        if touches.count >= 3 && Settings.shared.threeFingerSwipe {
            TouchKeyboardController.shared.handleOutsideGestureBegan(at: multiStartCentroid)
            mode = .swipe
        } else {
            if touches.count == 2 && Settings.shared.twoFingerScroll {
                injector.scroll(dx: 0, dy: 0, at: multiStartCentroid, phase: .mayBegin)
            }
            mode = .multiPending
        }
    }

    private func handleMultiPending(_ touches: [TouchPoint]) {
        if touches.isEmpty {
            let startPoints = Array(multiStartPositions.values)
            if Settings.shared.palmRejection,
               startPoints.count == 2,
               let top = startPoints.min(by: { $0.y < $1.y }),
               let bottom = startPoints.max(by: { $0.y < $1.y }),
               (bottom.y - top.y) > Thresholds.palmVerticalSeparation,
               Self.distance(bottom, top) > Thresholds.palmTotalSeparation,
               (now - startTime) < 0.45 {
                // Stylus/finger tap while palm was resting lower on the screen: click at the upper contact!
                completeSingleTap(at: top)
                mode = .idle
                return
            }

            if (now - startTime) < Thresholds.twoFingerTapMaxDuration,
               maxCentroidDrift <= Thresholds.tapMoveTolerance {
                if multiEnteredFromSingle {
                    completeSingleTap(at: startPoint)
                } else if multiValidFrames <= 4 {
                    completeSingleTap(at: multiStartCentroid)
                }
            }
            mode = .idle
            return
        }
        if touches.count >= 3 && !multiLifting {
            if Settings.shared.threeFingerSwipe { beginMulti(touches) } else { mode = .waitLift }
            return
        }
        let activePoints = tracked(touches)
        guard activePoints.count >= 2 else {
            if !multiLifting,
               activePoints.count == 1,
               (now - startTime) < Thresholds.twoFingerTapMaxDuration,
               maxCentroidDrift <= Thresholds.tapMoveTolerance {
                let remainingID = activePoints[0].id
                if let liftedEntry = multiStartPositions.first(where: { $0.key != remainingID }),
                   Self.distance(liftedEntry.value, activePoints[0].p) > 90.0 {
                    completeSingleTap(at: liftedEntry.value)
                    mode = .waitLift
                    return
                }
            }
            multiLifting = true
            return
        }
        guard !multiLifting else { return }

        // Stationary Palm Anchor vs Moving Universal Stylus Detection:
        // Only classify as "stylus + resting palm" when the stationary contact is in a true palm-heel geometry
        // (significantly lower on screen `> 75pt` and separated `> 140pt`), so thumb-pivot two-finger rotations
        // in Maps and fast two-finger swipes in Photos/Browsers are never hijacked into 1-finger mouse drags!
        if Settings.shared.palmRejection && multiValidFrames >= 4 {
            var movingContact: TouchPoint?
            var stationaryContact: TouchPoint?

            for point in activePoints {
                let startPos = multiStartPositions[point.id] ?? point.p
                let moved = Self.distance(point.p, startPos)
                if moved >= Thresholds.movingStylusMinMove {
                    movingContact = point
                } else if moved <= Thresholds.stationaryPalmMaxMove {
                    stationaryContact = point
                }
            }

            if let stylus = movingContact,
               let palm = stationaryContact,
               (palm.p.y - stylus.p.y) > Thresholds.palmVerticalSeparation,
               Self.distance(palm.p, stylus.p) > Thresholds.palmTotalSeparation {
                let stylusStart = multiStartPositions[stylus.id] ?? stylus.p
                primaryID = stylus.id
                startPoint = stylusStart
                lastPoint = stylus.p
                TouchKeyboardController.shared.handleOutsideGestureBegan(at: stylusStart)
                injector.move(to: stylusStart)
                injector.mouseDown(at: stylusStart)
                injector.drag(to: stylus.p)
                mode = .dragging
                return
            }
        }

        multiValidFrames += 1
        let currentCentroid = Self.centroid(activePoints)
        let currentSpan = max(Self.span(activePoints), 1.0)
        let currentAngle = Self.angle(activePoints)
        let centroidDelta = Self.distance(currentCentroid, multiStartCentroid)
        maxCentroidDrift = max(maxCentroidDrift, centroidDelta)
        let spanRatio = abs(currentSpan / multiStartDistance - 1.0)
        let angleDegrees = Self.shortestAngleDegrees(from: multiStartAngle, to: currentAngle)

        // Two-finger bottom-edge swipe-up also reveals the macOS Dock:
        let multiDisplayBounds = Self.displayBounds(for: multiStartCentroid)
        let multiDY = currentCentroid.y - multiStartCentroid.y
        let multiDX = currentCentroid.x - multiStartCentroid.x
        if multiDisplayBounds.height > 0,
           multiStartCentroid.y >= (multiDisplayBounds.maxY - Thresholds.bottomEdgeDockZoneHeight),
           multiDY <= -Thresholds.bottomEdgeSwipeUpDistance,
           abs(multiDX) <= abs(multiDY) * 1.6 {
            TouchKeyboardController.shared.dismiss()
            startPoint = multiStartCentroid
            injector.revealDock(at: multiStartCentroid, displayBounds: multiDisplayBounds)
            mode = .dockSwipeUp
            return
        }

        let wantsRotate = abs(angleDegrees) >= Thresholds.rotateStartDegrees
        let wantsPinch = Settings.shared.pinchZoom && spanRatio > Thresholds.pinchStartRatio && (spanRatio * 115.0) > centroidDelta

        if wantsRotate || wantsPinch {
            TouchKeyboardController.shared.handleOutsideGestureBegan(at: currentCentroid)
            enterPinchRotate(
                at: currentCentroid,
                currentSpan: currentSpan,
                currentAngle: currentAngle,
                startRotate: wantsRotate,
                startPinch: wantsPinch
            )
        } else if Settings.shared.twoFingerScroll && centroidDelta > Thresholds.scrollStartDistance {
            TouchKeyboardController.shared.handleOutsideGestureBegan(at: currentCentroid)
            mode = .scrolling
            let rawDX = currentCentroid.x - multiStartCentroid.x
            let rawDY = currentCentroid.y - multiStartCentroid.y
            isHorizontalScroll = abs(rawDX) > abs(rawDY) * 1.30

            injector.move(to: multiStartCentroid)
            scrollVelocity = .zero
            peakScrollVelocity = .zero
            peakVelocityTime = now
            lastScrollTime = now

            let sendDX = isHorizontalScroll ? Double(rawDX) * Thresholds.horizontalSwipeGain : Double(rawDX)
            let sendDY = isHorizontalScroll ? 0.0 : Double(rawDY)
            injector.scroll(
                dx: sendDX,
                dy: sendDY,
                at: currentCentroid,
                phase: .began
            )
            lastCentroid = currentCentroid
            lastDistance = currentSpan
            lastAngle = currentAngle
        } else if (now - startTime) > 1.5 && centroidDelta < Thresholds.scrollStartDistance && spanRatio < Thresholds.pinchStartRatio {
            maxFingers = 99
        }
    }

    private func handleScrolling(_ touches: [TouchPoint]) {
        let activePoints = tracked(touches)
        guard activePoints.count >= 2 else {
            let totalDX = lastCentroid.x - multiStartCentroid.x
            let totalDY = lastCentroid.y - multiStartCentroid.y

            injector.scroll(dx: 0, dy: 0, at: lastCentroid, phase: .ended)

            // Universal 2-finger horizontal swipe event + momentum for back/forward and previous/next across all apps
            if isHorizontalScroll && abs(totalDX) >= Thresholds.horizontalNavDistance && abs(totalDX) > abs(totalDY) * 1.4 {
                let goPrevious = Settings.shared.invertScroll ? (totalDX < 0) : (totalDX > 0)
                injector.swipe(goPrevious ? .left : .right, at: lastCentroid)
            }

            if Settings.shared.momentum && ((now - lastScrollTime) < 0.18 || (now - peakVelocityTime) < 0.22) {
                startMomentum(totalDX: totalDX)
            }
            mode = touches.isEmpty ? .idle : .waitLift
            return
        }

        let currentCentroid = Self.centroid(activePoints)
        let currentSpan = max(Self.span(activePoints), 1.0)
        let currentAngle = Self.angle(activePoints)
        let totalCentroidDelta = Self.distance(currentCentroid, multiStartCentroid)
        maxCentroidDrift = max(maxCentroidDrift, totalCentroidDelta)

        // Seamless transition from early scroll into Pinch/Rotate if the user twists or pinches their fingers
        // within the first 48pt of centroid drift.
        if maxCentroidDrift < 48.0 {
            let totalAngleDegrees = Self.shortestAngleDegrees(from: multiStartAngle, to: currentAngle)
            let spanRatio = abs(currentSpan / multiStartDistance - 1.0)
            let wantsRotate = abs(totalAngleDegrees) >= 4.2
            let wantsPinch = Settings.shared.pinchZoom && spanRatio >= 0.13
            if wantsRotate || wantsPinch {
                injector.scroll(dx: 0, dy: 0, at: currentCentroid, phase: .ended)
                enterPinchRotate(
                    at: currentCentroid,
                    currentSpan: currentSpan,
                    currentAngle: currentAngle,
                    startRotate: wantsRotate,
                    startPinch: wantsPinch
                )
                return
            }
        }

        let currentTime = now
        let dt = max(currentTime - lastScrollTime, 0.001)
        let dx = currentCentroid.x - lastCentroid.x
        let dy = currentCentroid.y - lastCentroid.y

        if dx != 0 || dy != 0 {
            let sendDX = isHorizontalScroll ? Double(dx) * Thresholds.horizontalSwipeGain : Double(dx)
            let sendDY = isHorizontalScroll ? 0.0 : Double(dy)
            injector.scroll(dx: sendDX, dy: sendDY, at: currentCentroid, phase: .changed)

            let instantaneous = CGVector(dx: CGFloat(sendDX) / dt, dy: CGFloat(sendDY) / dt)
            scrollVelocity = CGVector(
                dx: scrollVelocity.dx * 0.4 + instantaneous.dx * 0.6,
                dy: scrollVelocity.dy * 0.4 + instantaneous.dy * 0.6
            )
            if hypot(scrollVelocity.dx, scrollVelocity.dy) >= hypot(peakScrollVelocity.dx, peakScrollVelocity.dy) * 0.85 {
                peakScrollVelocity = scrollVelocity
                peakVelocityTime = currentTime
            }
            lastScrollTime = currentTime
        }
        lastCentroid = currentCentroid
        lastDistance = currentSpan
        lastAngle = currentAngle
    }

    // MARK: - Unified Two-Finger Pinch Zoom & Rotation

    private func enterPinchRotate(
        at centroid: CGPoint,
        currentSpan: CGFloat,
        currentAngle: CGFloat,
        startRotate: Bool,
        startPinch: Bool
    ) {
        mode = .pinchRotate
        injector.move(to: centroid)

        if startRotate {
            rotateBegan = true
            let initialDegrees = Double(Self.shortestAngleDegrees(from: multiStartAngle, to: currentAngle))
            injector.rotate(0, at: centroid, phase: .began)
            if abs(initialDegrees) > 0.05 {
                injector.rotate(initialDegrees, at: centroid, phase: .changed)
            }
        }
        if startPinch {
            magnifyBegan = true
            let initialScale = Double(currentSpan / multiStartDistance - 1.0)
            injector.magnify(0, at: centroid, phase: .began)
            if abs(initialScale) > 0.001 {
                injector.magnify(initialScale, at: centroid, phase: .changed)
            }
        }

        lastCentroid = centroid
        lastDistance = currentSpan
        lastAngle = currentAngle
    }

    private func handlePinchRotate(_ touches: [TouchPoint]) {
        let activePoints = tracked(touches)
        guard activePoints.count >= 2 else {
            endPinchRotate(at: lastCentroid)
            mode = touches.isEmpty ? .idle : .waitLift
            return
        }

        let currentCentroid = Self.centroid(activePoints)
        let currentSpan = max(Self.span(activePoints), 1.0)
        let currentAngle = Self.angle(activePoints)

        // 1. Rotation update
        let stepDegrees = Self.shortestAngleDegrees(from: lastAngle, to: currentAngle)
        if !rotateBegan {
            let totalDegrees = Self.shortestAngleDegrees(from: multiStartAngle, to: currentAngle)
            if abs(totalDegrees) >= Thresholds.rotateStartDegrees {
                rotateBegan = true
                injector.rotate(0, at: currentCentroid, phase: .began)
                injector.rotate(Double(totalDegrees), at: currentCentroid, phase: .changed)
                lastAngle = currentAngle
            }
        } else if abs(stepDegrees) >= 0.08 {
            injector.rotate(Double(stepDegrees), at: currentCentroid, phase: .changed)
            lastAngle = currentAngle
        }

        // 2. Pinch Magnification update
        if Settings.shared.pinchZoom {
            let scaleDelta = Double(currentSpan / lastDistance - 1.0)
            if !magnifyBegan {
                let totalSpanRatio = abs(currentSpan / multiStartDistance - 1.0)
                if totalSpanRatio >= Thresholds.pinchStartRatio {
                    magnifyBegan = true
                    injector.magnify(0, at: currentCentroid, phase: .began)
                    injector.magnify(Double(currentSpan / multiStartDistance - 1.0), at: currentCentroid, phase: .changed)
                    lastDistance = currentSpan
                }
            } else if abs(scaleDelta) >= 0.0008 {
                injector.magnify(scaleDelta, at: currentCentroid, phase: .changed)
                lastDistance = currentSpan
            }
        }

        lastCentroid = currentCentroid
    }

    private func endPinchRotate(at point: CGPoint) {
        if rotateBegan {
            injector.rotate(0, at: point, phase: .ended)
            rotateBegan = false
        }
        if magnifyBegan {
            injector.magnify(0, at: point, phase: .ended)
            magnifyBegan = false
        }
    }

    private func handleSwipe(_ touches: [TouchPoint]) {
        guard !touches.isEmpty else {
            mode = .idle
            return
        }
        let activePoints = tracked(touches)
        guard activePoints.count >= 2 else { return }

        let currentCentroid = Self.centroid(activePoints)
        let dx = currentCentroid.x - multiStartCentroid.x
        let dy = currentCentroid.y - multiStartCentroid.y
        guard max(abs(dx), abs(dy)) > Thresholds.swipeCommitDistance else { return }

        if abs(dx) > abs(dy) {
            injector.controlArrow(dx < 0 ? .right : .left)
        } else {
            injector.controlArrow(dy < 0 ? .up : .down)
        }
        mode = .waitLift
    }

    // MARK: - Momentum Scrolling

    private func startMomentum(totalDX: CGFloat = 0) {
        var velocity = scrollVelocity
        if (now - peakVelocityTime) < 0.22 && hypot(peakScrollVelocity.dx, peakScrollVelocity.dy) > hypot(velocity.dx, velocity.dy) {
            velocity = peakScrollVelocity
        }
        if isHorizontalScroll && abs(totalDX) >= 36.0 && abs(velocity.dx) < 850.0 {
            velocity = CGVector(dx: totalDX > 0 ? 850.0 : -850.0, dy: 0)
        }

        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > Thresholds.minMomentumSpeed else { return }

        if speed > Thresholds.maxMomentumSpeed {
            let scale = Thresholds.maxMomentumSpeed / speed
            velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
        }

        let targetPoint = lastCentroid
        momentumStarted = false
        let dt = Thresholds.momentumFrameInterval
        let timer = Timer(timeInterval: dt, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            velocity = CGVector(
                dx: velocity.dx * Thresholds.momentumDecay,
                dy: velocity.dy * Thresholds.momentumDecay
            )
            if hypot(velocity.dx, velocity.dy) < Thresholds.stopMomentumSpeed {
                self.injector.scroll(dx: 0, dy: 0, at: targetPoint, phase: nil, momentum: .end)
                timer.invalidate()
                self.momentumTimer = nil
                return
            }
            self.injector.scroll(
                dx: Double(velocity.dx) * dt,
                dy: Double(velocity.dy) * dt,
                at: targetPoint,
                phase: nil,
                momentum: self.momentumStarted ? .continue : .begin
            )
            self.momentumStarted = true
        }
        RunLoop.main.add(timer, forMode: .common)
        momentumTimer = timer
    }

    private func stopMomentum() {
        guard let timer = momentumTimer else { return }
        timer.invalidate()
        momentumTimer = nil
        injector.scroll(dx: 0, dy: 0, at: lastCentroid, phase: nil, momentum: .end)
    }

    // MARK: - Geometry & Filtering Helpers

    /// Merges contacts that are closer than `splitContactMergeDistance` (caused by a single flat fingertip pad
    /// briefly registering two adjacent capacitive peaks on the digitizer).
    private static func coalesceSplitContacts(_ touches: [TouchPoint]) -> [TouchPoint] {
        guard touches.count >= 2 else { return touches }
        var result: [TouchPoint] = []
        result.reserveCapacity(touches.count)
        for candidate in touches {
            let isSplitDuplicate = result.contains { existing in
                distance(existing.p, candidate.p) < Thresholds.splitContactMergeDistance
            }
            if !isSplitDuplicate {
                result.append(candidate)
            }
        }
        return result
    }

    @inline(__always)
    private func tracked(_ touches: [TouchPoint]) -> [TouchPoint] {
        touches.filter { trackedIDs.contains($0.id) }
    }

    @inline(__always)
    private static func centroid(_ touches: [TouchPoint]) -> CGPoint {
        guard !touches.isEmpty else { return .zero }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for touch in touches {
            sumX += touch.p.x
            sumY += touch.p.y
        }
        let count = CGFloat(touches.count)
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    @inline(__always)
    private static func span(_ touches: [TouchPoint]) -> CGFloat {
        guard touches.count >= 2 else { return 0 }
        return distance(touches[0].p, touches[1].p)
    }

    @inline(__always)
    private static func angle(_ touches: [TouchPoint]) -> CGFloat {
        guard touches.count >= 2 else { return 0 }
        let pair = touches[0].id < touches[1].id ? (touches[0], touches[1]) : (touches[1], touches[0])
        return atan2(pair.1.p.y - pair.0.p.y, pair.1.p.x - pair.0.p.x)
    }

    /// Returns the shortest angular difference in degrees, where counter-clockwise rotation on screen is positive (`+`)
    /// and clockwise rotation is negative (`-`), matching `NSEvent.rotation`.
    @inline(__always)
    private static func shortestAngleDegrees(from startRad: CGFloat, to endRad: CGFloat) -> CGFloat {
        var diff = endRad - startRad
        while diff > .pi { diff -= 2.0 * .pi }
        while diff < -.pi { diff += 2.0 * .pi }
        return -diff * 180.0 / .pi
    }

    @inline(__always)
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func displayBounds(for point: CGPoint) -> CGRect {
        var displayID: CGDirectDisplayID = CGMainDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(point, 1, &displayID, &count)
        return CGDisplayBounds(displayID)
    }
}
