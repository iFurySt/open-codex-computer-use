import CoreGraphics
import Foundation

struct CursorMotionParameters: Equatable {
    static let `default` = CursorMotionParameters()
}

struct CursorMotionSegment: Equatable {
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
}

struct CursorMotionPath: Equatable {
    let start: CGPoint
    let end: CGPoint
    let startControl: CGPoint?
    let arc: CGPoint?
    let arcIn: CGPoint?
    let arcOut: CGPoint?
    let endControl: CGPoint?
    let segments: [CursorMotionSegment]
    let curveScale: CGFloat

    init(
        start: CGPoint,
        end: CGPoint,
        startControl: CGPoint? = nil,
        arc: CGPoint? = nil,
        arcIn: CGPoint? = nil,
        arcOut: CGPoint? = nil,
        endControl: CGPoint? = nil,
        segments: [CursorMotionSegment],
        curveScale: CGFloat = 1
    ) {
        self.start = start
        self.end = end
        self.startControl = startControl
        self.arc = arc
        self.arcIn = arcIn
        self.arcOut = arcOut
        self.endControl = endControl
        self.segments = segments
        self.curveScale = curveScale
    }

    init(start: CGPoint, end: CGPoint, curveDirection: CGFloat? = nil, curveScale: CGFloat = 1) {
        let delta = end - start
        let distance = max(delta.length, 1)
        let normal = delta.perpendicular.normalized
        let resolvedCurveDirection = curveDirection ?? (delta.dx >= 0 ? 1 : -1)
        let resolvedCurveScale = max(curveScale, 0)
        let curveAmount = min(max(distance * 0.22, 28), 110) * resolvedCurveScale
        let controlOffset = normal.scaled(by: curveAmount * resolvedCurveDirection)
        let control1Base = CGPoint(
            x: start.x + (delta.dx * (resolvedCurveScale == 0 ? 1.0 / 3.0 : 0.18)),
            y: start.y + (delta.dy * (resolvedCurveScale == 0 ? 1.0 / 3.0 : 0.10))
        )
        let control2Base = CGPoint(
            x: start.x + (delta.dx * (resolvedCurveScale == 0 ? 2.0 / 3.0 : 0.80)),
            y: start.y + (delta.dy * (resolvedCurveScale == 0 ? 2.0 / 3.0 : 0.96))
        )
        let control1 = control1Base + controlOffset
        let control2 = control2Base + controlOffset.scaled(by: 0.48)

        self.init(
            start: start,
            end: end,
            startControl: control1,
            endControl: control2,
            segments: [
                CursorMotionSegment(end: end, control1: control1, control2: control2),
            ],
            curveScale: resolvedCurveScale
        )
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        path.move(to: start)

        for segment in segments {
            path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }

        return path
    }

    func point(at progress: CGFloat) -> CGPoint {
        sample(at: progress).point
    }

    func tangent(at progress: CGFloat) -> CGVector {
        sample(at: progress).tangent
    }

    func sample(at progress: CGFloat) -> (point: CGPoint, tangent: CGVector) {
        guard !segments.isEmpty else {
            return (start, CGVector(dx: 1, dy: 0))
        }

        let clamped = progress.clamped(to: 0...1)
        let segmentCount = segments.count
        let segmentIndex: Int
        let localT: CGFloat

        if clamped >= 1 {
            segmentIndex = segmentCount - 1
            localT = 1
        } else {
            let scaled = clamped * CGFloat(segmentCount)
            segmentIndex = min(Int(scaled), segmentCount - 1)
            localT = scaled - CGFloat(segmentIndex)
        }

        let segment = segments[segmentIndex]
        let segmentStart = segmentIndex == 0 ? start : segments[segmentIndex - 1].end
        let point = sampleCubic(
            start: segmentStart,
            control1: segment.control1,
            control2: segment.control2,
            end: segment.end,
            t: localT
        )
        let tangent = sampleCubicTangent(
            start: segmentStart,
            control1: segment.control1,
            control2: segment.control2,
            end: segment.end,
            t: localT
        ).normalized
        return (point, tangent)
    }

    func sampledConstraintPoints(samplesPerSegment: Int = 6) -> [CGPoint] {
        let totalSteps = max(segments.count * max(samplesPerSegment, 1), 1)
        return (1...totalSteps).map { step in
            point(at: CGFloat(step) / CGFloat(totalSteps))
        }
    }

    func measure(bounds: CGRect?, minStepDistance: CGFloat = 0.01, samplesPerSegment: Int = 24) -> CursorMotionMeasurement {
        var totalLength: CGFloat = 0
        var angleChangeEnergy: CGFloat = 0
        var maxAngleChange: CGFloat = 0
        var totalTurn: CGFloat = 0
        var staysInBounds = bounds?.contains(start, padding: 20) ?? true
        var previousPoint = start
        var previousAngle: CGFloat?

        let totalSteps = max(segments.count * max(samplesPerSegment, 1), 1)
        for step in 1...totalSteps {
            let progress = CGFloat(step) / CGFloat(totalSteps)
            let point = point(at: progress)
            let delta = point - previousPoint
            let stepLength = delta.length

            if let bounds, staysInBounds {
                staysInBounds = bounds.contains(point, padding: 20)
            }

            if stepLength > minStepDistance {
                let angle = atan2(delta.dy, delta.dx)
                totalLength += stepLength

                if let previousAngle {
                    var angleDelta = angle - previousAngle
                    while angleDelta > .pi {
                        angleDelta -= (.pi * 2)
                    }
                    while angleDelta < -.pi {
                        angleDelta += (.pi * 2)
                    }

                    angleChangeEnergy += angleDelta * angleDelta
                    let absoluteDelta = abs(angleDelta)
                    maxAngleChange = max(maxAngleChange, absoluteDelta)
                    totalTurn += absoluteDelta
                }

                previousAngle = angle
                previousPoint = point
            }
        }

        return CursorMotionMeasurement(
            length: totalLength,
            angleChangeEnergy: angleChangeEnergy,
            maxAngleChange: maxAngleChange,
            totalTurn: totalTurn,
            staysInBounds: staysInBounds
        )
    }
}

struct CursorMotionMeasurement: Equatable {
    let length: CGFloat
    let angleChangeEnergy: CGFloat
    let maxAngleChange: CGFloat
    let totalTurn: CGFloat
    let staysInBounds: Bool
}

enum CursorMotionKind: String, Equatable {
    case base
    case arched
}

struct CursorMotionCandidate: Identifiable, Equatable {
    let id: String
    let kind: CursorMotionKind
    let side: Int
    let tableAScale: CGFloat?
    let tableBScale: CGFloat?
    let path: CursorMotionPath
    let measurement: CursorMotionMeasurement
    let score: CGFloat
}

struct CursorMotionSpringConfiguration: Equatable {
    let response: CGFloat
    let dampingFraction: CGFloat
    let stiffness: CGFloat
    let drag: CGFloat
    let dt: CGFloat
    let closeEnoughProgressThreshold: CGFloat
    let closeEnoughDistanceThreshold: CGFloat
    let idleVelocityThreshold: CGFloat

    static let official: CursorMotionSpringConfiguration = {
        let response: CGFloat = 1.4
        let dampingFraction: CGFloat = 0.9
        let dt: CGFloat = 1.0 / 240.0
        let idleVelocityThreshold: CGFloat = 28_800
        let rawStiffness = response > 0 ? pow((2 * .pi) / response, 2) : .infinity
        let stiffness = min(rawStiffness, idleVelocityThreshold)
        let drag = 2 * dampingFraction * sqrt(stiffness)

        return CursorMotionSpringConfiguration(
            response: response,
            dampingFraction: dampingFraction,
            stiffness: stiffness,
            drag: drag,
            dt: dt,
            closeEnoughProgressThreshold: 1,
            closeEnoughDistanceThreshold: 0.01,
            idleVelocityThreshold: idleVelocityThreshold
        )
    }()
}

struct CursorMotionSpringState: Equatable {
    var time: CGFloat = 0
    var velocity: CGFloat = 0
    var force: CGFloat = 0
}

enum CursorMotionProgressAnimator {
    static func advance(
        current: CGFloat,
        target: CGFloat = 1,
        state: CursorMotionSpringState,
        configuration: CursorMotionSpringConfiguration = .official
    ) -> (current: CGFloat, state: CursorMotionSpringState) {
        let halfDT = configuration.dt * 0.5
        let velocityHalf = state.velocity + (state.force * halfDT)
        let nextCurrent = current + (velocityHalf * configuration.dt)
        let force = (configuration.stiffness * (target - nextCurrent)) + ((-configuration.drag) * velocityHalf)
        let velocity = velocityHalf + (force * halfDT)

        return (
            nextCurrent,
            CursorMotionSpringState(
                time: state.time + configuration.dt,
                velocity: velocity,
                force: force
            )
        )
    }

    static func advance(
        current: CGFloat,
        target: CGFloat = 1,
        state: CursorMotionSpringState,
        configuration: CursorMotionSpringConfiguration = .official,
        to targetTime: CGFloat
    ) -> (current: CGFloat, state: CursorMotionSpringState) {
        var adjustedState = state
        var adjustedCurrent = current

        if (targetTime - adjustedState.time) > 1 {
            adjustedState.time = targetTime - (1.0 / 60.0)
        }

        while adjustedState.time < targetTime {
            (adjustedCurrent, adjustedState) = advance(
                current: adjustedCurrent,
                target: target,
                state: adjustedState,
                configuration: configuration
            )
        }

        return (adjustedCurrent, adjustedState)
    }

    static func isCloseEnough(
        progress: CGFloat,
        target: CGFloat = 1,
        configuration: CursorMotionSpringConfiguration = .official
    ) -> Bool {
        progress >= configuration.closeEnoughProgressThreshold
            && abs(target - progress) <= configuration.closeEnoughDistanceThreshold
    }

    static func closeEnoughTime(
        configuration: CursorMotionSpringConfiguration = .official
    ) -> CGFloat {
        var current: CGFloat = 0
        var state = CursorMotionSpringState()
        var step = 0

        while step < 4_096 {
            step += 1
            let targetTime = CGFloat(step) * configuration.dt
            (current, state) = advance(
                current: current,
                target: 1,
                state: state,
                configuration: configuration,
                to: targetTime
            )

            if isCloseEnough(progress: current, configuration: configuration) {
                return state.time
            }
        }

        return 1.43
    }
}

enum OfficialCursorMotionModel {
    static let minimumStepDistance: CGFloat = 0.01
    static let guideVectorInLocalBasis = CGVector(dx: -0.6946583704589973, dy: 0.7193398003386512)
    static let tableA: [CGFloat] = [0.55, 0.8, 1.05]
    static let tableB: [CGFloat] = [0.65, 1.0, 1.35]
    static let closeEnoughTime = CursorMotionProgressAnimator.closeEnoughTime()

    private static let normalizationEpsilon: CGFloat = 0.001
    private static let sideBiasScale: CGFloat = 0.65
    private static let primaryDistanceScale: CGFloat = 0.41960295031576633
    private static let directSpanScale: CGFloat = 0.9
    private static let secondaryDistanceScale: CGFloat = 0.2765523188064277
    private static let arcDistanceScale: CGFloat = 0.5783555327868779
    private static let candidateArcMin: CGFloat = 38
    private static let candidateArcMax: CGFloat = 440
    private static let scoreExcessLengthWeight: CGFloat = 320
    private static let scoreAngleEnergyWeight: CGFloat = 140
    private static let scoreMaxAngleWeight: CGFloat = 180
    private static let scoreTotalTurnWeight: CGFloat = 18
    private static let scoreOutOfBoundsPenalty: CGFloat = 45

    static func makeCandidates(start: CGPoint, end: CGPoint, bounds: CGRect?) -> [CursorMotionCandidate] {
        let delta = end - start
        let distance = max(delta.length, normalizationEpsilon)
        let direction = delta.normalized
        let localNormal = direction.perpendicular
        let guide = direction.scaled(by: guideVectorInLocalBasis.dx)
            + localNormal.scaled(by: guideVectorInLocalBasis.dy)
        let reverseGuide = guide.scaled(by: -1)

        let (startExtentPre, endExtentPre) = binaryPiecewisePrimaryExtents(distance: distance)
        let startExtent = min(startExtentPre, clipPositiveRay(origin: start, direction: guide, bounds: bounds))
        let endExtent = min(endExtentPre, clipPositiveRay(origin: end, direction: reverseGuide, bounds: bounds))

        let startExtentScaled = min(
            max(startExtent * sideBiasScale, 0),
            clipPositiveRay(origin: start, direction: guide, bounds: bounds)
        )
        let endExtentScaled = min(
            max(endExtent * sideBiasScale, 0),
            clipPositiveRay(origin: end, direction: reverseGuide, bounds: bounds)
        )

        let fullStartControl = start + guide.scaled(by: startExtent)
        let fullEndControl = end - guide.scaled(by: endExtent)
        let scaledStartControl = start + guide.scaled(by: startExtentScaled)
        let scaledEndControl = end - guide.scaled(by: endExtentScaled)

        let rawHandleExtent = binaryPiecewiseHandleExtent(distance: distance)
        let rawArcExtent = (distance * arcDistanceScale).clamped(to: candidateArcMin...candidateArcMax)

        let midpoint = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        var signedNormal = localNormal
        let cross = (guide.dy * direction.dx) - (guide.dx * direction.dy)
        if cross < 0 {
            signedNormal = signedNormal.scaled(by: -1)
        }
        let arcAnchorBias = guide.scaled(by: startExtent * sideBiasScale)
        let forwardUnit = normalizedOrDefault(
            direction.scaled(by: distance) + signedNormal.scaled(by: rawArcExtent),
            minimumLength: rawHandleExtent
        )

        var candidates: [CursorMotionCandidate] = []
        candidates.append(
            makeCandidate(
                id: "base-full-guide",
                kind: .base,
                side: 0,
                tableAScale: nil,
                tableBScale: nil,
                path: CursorMotionPath(
                    start: start,
                    end: end,
                    startControl: fullStartControl,
                    endControl: fullEndControl,
                    segments: [
                        CursorMotionSegment(end: end, control1: fullStartControl, control2: fullEndControl),
                    ],
                    curveScale: 1
                ),
                distance: distance,
                bounds: bounds
            )
        )
        candidates.append(
            makeCandidate(
                id: "base-scaled-guide",
                kind: .base,
                side: 0,
                tableAScale: nil,
                tableBScale: nil,
                path: CursorMotionPath(
                    start: start,
                    end: end,
                    startControl: scaledStartControl,
                    endControl: scaledEndControl,
                    segments: [
                        CursorMotionSegment(end: end, control1: scaledStartControl, control2: scaledEndControl),
                    ],
                    curveScale: sideBiasScale
                ),
                distance: distance,
                bounds: bounds
            )
        )

        for outerScale in tableA {
            let anchorOffset = signedNormal.scaled(by: rawHandleExtent * outerScale)
            for innerScale in tableB {
                let tangentSpan = forwardUnit.scaled(by: rawArcExtent * innerScale)

                for side in [1, -1] {
                    let anchor = midpoint + arcAnchorBias + anchorOffset.scaled(by: CGFloat(side))
                    let arcIn = anchor - tangentSpan
                    let arcOut = anchor + tangentSpan
                    let path = CursorMotionPath(
                        start: start,
                        end: end,
                        startControl: fullStartControl,
                        arc: anchor,
                        arcIn: arcIn,
                        arcOut: arcOut,
                        endControl: fullEndControl,
                        segments: [
                            CursorMotionSegment(end: anchor, control1: fullStartControl, control2: arcIn),
                            CursorMotionSegment(end: end, control1: arcOut, control2: fullEndControl),
                        ],
                        curveScale: innerScale
                    )

                    candidates.append(
                        makeCandidate(
                            id: "a\(outerScale.cursorIdentifier)-b\(innerScale.cursorIdentifier)-\(side > 0 ? "positive" : "negative")",
                            kind: .arched,
                            side: side,
                            tableAScale: outerScale,
                            tableBScale: innerScale,
                            path: path,
                            distance: distance,
                            bounds: bounds
                        )
                    )
                }
            }
        }

        return candidates
    }

    static func chooseBestCandidate(from candidates: [CursorMotionCandidate]) -> CursorMotionCandidate? {
        guard !candidates.isEmpty else {
            return nil
        }

        let inBoundsCandidates = candidates.filter(\.measurement.staysInBounds)
        let pool = inBoundsCandidates.isEmpty ? candidates : inBoundsCandidates
        return pool.min { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.id < rhs.id
            }
            return lhs.score < rhs.score
        }
    }

    static func calibratedTravelDuration(distance: CGFloat, measurement: CursorMotionMeasurement) -> CGFloat {
        let weightedRatio = max((measurement.length / max(distance, 1)) - 1, 0)
        let distanceTerm = 0.18 + min(distance / 1300, 0.35)
        let curvatureTerm = min(weightedRatio, 1.5) * 0.18
        let settleTerm = min(weightedRatio, 1.0) * 0.04
        return max(distanceTerm + curvatureTerm + settleTerm, 0.23)
    }

    private static func makeCandidate(
        id: String,
        kind: CursorMotionKind,
        side: Int,
        tableAScale: CGFloat?,
        tableBScale: CGFloat?,
        path: CursorMotionPath,
        distance: CGFloat,
        bounds: CGRect?
    ) -> CursorMotionCandidate {
        let measurement = path.measure(bounds: bounds, minStepDistance: minimumStepDistance)
        let score = scoreCandidate(distance: distance, measurement: measurement)
        return CursorMotionCandidate(
            id: id,
            kind: kind,
            side: side,
            tableAScale: tableAScale,
            tableBScale: tableBScale,
            path: path,
            measurement: measurement,
            score: score
        )
    }

    private static func scoreCandidate(distance: CGFloat, measurement: CursorMotionMeasurement) -> CGFloat {
        let excessLengthRatio = max((measurement.length / max(distance, 1)) - 1, 0)
        return (excessLengthRatio * scoreExcessLengthWeight)
            + (measurement.angleChangeEnergy * scoreAngleEnergyWeight)
            + (measurement.maxAngleChange * scoreMaxAngleWeight)
            + (measurement.totalTurn * scoreTotalTurnWeight)
            + (measurement.staysInBounds ? 0 : scoreOutOfBoundsPenalty)
    }

    private static func binaryPiecewisePrimaryExtents(distance: CGFloat) -> (startExtent: CGFloat, endExtent: CGFloat) {
        let primary = distance * primaryDistanceScale
        let direct = distance * directSpanScale
        let secondary = distance * 0.15
        let lowCutoff: CGFloat = 48
        let highCutoff: CGFloat = 640

        if primary < lowCutoff {
            return (lowCutoff, lowCutoff)
        }
        if primary < highCutoff {
            return (primary, direct)
        }
        if secondary < highCutoff {
            return (highCutoff, lowCutoff)
        }
        return (highCutoff, highCutoff)
    }

    private static func binaryPiecewiseHandleExtent(distance: CGFloat) -> CGFloat {
        let raw = distance * secondaryDistanceScale
        if raw < 50 {
            return 50
        }
        if raw < 640 {
            return raw
        }
        return 520
    }

    private static func clipPositiveRay(origin: CGPoint, direction: CGVector, bounds: CGRect?) -> CGFloat {
        guard let bounds else {
            return .infinity
        }

        var limit = CGFloat.infinity
        if direction.dx > 0 {
            limit = min(limit, (bounds.maxX - origin.x) / direction.dx)
        } else if direction.dx < 0 {
            limit = min(limit, (bounds.minX - origin.x) / direction.dx)
        }

        if direction.dy > 0 {
            limit = min(limit, (bounds.maxY - origin.y) / direction.dy)
        } else if direction.dy < 0 {
            limit = min(limit, (bounds.minY - origin.y) / direction.dy)
        }

        return max(limit, 0)
    }

    private static func normalizedOrDefault(_ vector: CGVector, minimumLength: CGFloat) -> CGVector {
        let length = vector.length
        if length < minimumLength || length < normalizationEpsilon {
            return CGVector(dx: 1, dy: 0)
        }
        return vector.scaled(by: 1 / length)
    }
}

enum HeadingDrivenCursorMotionModel {
    private static let defaultStartHandle: CGFloat = 0.29
    private static let defaultEndHandle: CGFloat = 0.08
    private static let defaultArcSize: CGFloat = 0.06
    private static let defaultArcFlow: CGFloat = 0.64
    private static let normalizationEpsilon: CGFloat = 0.001

    static func makeCandidates(
        start: CGPoint,
        end: CGPoint,
        bounds: CGRect?,
        startForward: CGVector,
        endForward: CGVector
    ) -> [CursorMotionCandidate] {
        let metrics = MotionMetrics(start: start, end: end)
        let resolvedStartForward = normalizedOrDefault(startForward)
        let resolvedEndForward = normalizedOrDefault(endForward)
        let preferredSide = preferredTurnSide(
            metrics: metrics,
            startForward: resolvedStartForward,
            endForward: resolvedEndForward
        )
        let scoringContext = MotionScoringContext(
            metrics: metrics,
            startForward: resolvedStartForward,
            endForward: resolvedEndForward,
            preferredSide: preferredSide
        )

        return descriptors(for: metrics, preferredSide: preferredSide).map { descriptor in
            let path = makePath(
                from: start,
                to: end,
                metrics: metrics,
                descriptor: descriptor,
                startForward: resolvedStartForward,
                endForward: resolvedEndForward
            )
            return makeCandidate(
                id: descriptor.id,
                kind: descriptor.kind,
                side: descriptor.side,
                tableAScale: nil,
                tableBScale: nil,
                path: path,
                bounds: bounds,
                context: scoringContext,
                descriptor: descriptor
            )
        }
    }

    static func chooseBestCandidate(from candidates: [CursorMotionCandidate]) -> CursorMotionCandidate? {
        guard !candidates.isEmpty else {
            return nil
        }

        let inBoundsCandidates = candidates.filter(\.measurement.staysInBounds)
        let pool = inBoundsCandidates.isEmpty ? candidates : inBoundsCandidates
        return pool.min { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.id < rhs.id
            }
            return lhs.score < rhs.score
        }
    }

    static func calibratedTravelDuration(distance: CGFloat, measurement: CursorMotionMeasurement) -> CGFloat {
        OfficialCursorMotionModel.calibratedTravelDuration(distance: distance, measurement: measurement)
    }

    private static func makePath(
        from start: CGPoint,
        to end: CGPoint,
        metrics: MotionMetrics,
        descriptor: MotionDescriptor,
        startForward: CGVector,
        endForward: CGVector
    ) -> CursorMotionPath {
        let distance = metrics.distance
        let direction = metrics.direction
        let normal = metrics.normal
        let resolvedFlow = (defaultArcFlow + descriptor.flowShift).clamped(to: 0...1)
        let flowBias = (resolvedFlow - 0.5) * distance * 0.18

        let baseStartReach = distance * (0.10 + defaultStartHandle * 0.56)
        let baseEndReach = distance * (0.11 + defaultEndHandle * 0.62)
        let distanceLift = 0.68 + (metrics.farFactor * 0.56)
        let baseArcHeight = min(
            max(distance * (0.10 + defaultArcSize * 0.92) * descriptor.arcScale * distanceLift, 20),
            distance * 0.96
        )

        let sideSign = CGFloat(descriptor.side)
        let arcVector = CGVector(
            dx: normal.dx * baseArcHeight * sideSign,
            dy: normal.dy * baseArcHeight * sideSign
        )

        let startGuide = resolvedGuide(
            line: direction,
            forward: startForward,
            normal: normal,
            sideSign: sideSign,
            lineWeight: descriptor.startLineWeight,
            headingWeight: descriptor.startHeadingWeight,
            normalBias: descriptor.startGuideNormalBias
        )
        let endGuide = resolvedGuide(
            line: direction,
            forward: endForward,
            normal: normal,
            sideSign: sideSign,
            lineWeight: descriptor.endLineWeight,
            headingWeight: descriptor.endHeadingWeight,
            normalBias: descriptor.endGuideNormalBias
        )

        let startReach = max(baseStartReach * descriptor.startReachScale + flowBias * descriptor.startFlowWeight, 12)
        let endReach = max(baseEndReach * descriptor.endReachScale - flowBias * descriptor.endFlowWeight, 12)
        let control1Base = start + startGuide.scaled(by: startReach)
        let control2Base = end - endGuide.scaled(by: endReach)

        let control1 = control1Base + arcVector.scaled(by: descriptor.startNormalScale)
        let control2 = control2Base + arcVector.scaled(by: descriptor.endNormalScale)
        let resolvedArcHeight = baseArcHeight * max(
            abs(descriptor.startNormalScale),
            abs(descriptor.endNormalScale),
            0.12
        )

        return CursorMotionPath(
            start: start,
            end: end,
            startControl: control1,
            endControl: control2,
            segments: [
                CursorMotionSegment(end: end, control1: control1, control2: control2)
            ],
            curveScale: resolvedArcHeight
        )
    }

    private static func makeCandidate(
        id: String,
        kind: CursorMotionKind,
        side: Int,
        tableAScale: CGFloat?,
        tableBScale: CGFloat?,
        path: CursorMotionPath,
        bounds: CGRect?,
        context: MotionScoringContext,
        descriptor: MotionDescriptor
    ) -> CursorMotionCandidate {
        let measurement = path.measure(bounds: bounds, minStepDistance: OfficialCursorMotionModel.minimumStepDistance)
        let score = scoreCandidate(
            measurement: measurement,
            path: path,
            descriptor: descriptor,
            context: context
        )

        return CursorMotionCandidate(
            id: id,
            kind: kind,
            side: side,
            tableAScale: tableAScale,
            tableBScale: tableBScale,
            path: path,
            measurement: measurement,
            score: score
        )
    }

    private static func scoreCandidate(
        measurement: CursorMotionMeasurement,
        path: CursorMotionPath,
        descriptor: MotionDescriptor,
        context: MotionScoringContext
    ) -> CGFloat {
        let distance = max(context.metrics.distance, 1)
        let excessLengthRatio = max((measurement.length / distance) - 1, 0)
        let startTangent = normalizedOrDefault(path.tangent(at: 0.04))
        let endTangent = normalizedOrDefault(path.tangent(at: 0.96))
        let startHeadingError = abs(signedAngle(from: context.startForward, to: startTangent))
        let endHeadingError = abs(signedAngle(from: endTangent, to: context.endForward))

        var score = descriptor.scoreBias
        score += excessLengthRatio * 180
        score += measurement.angleChangeEnergy * 90
        score += measurement.maxAngleChange * 85
        score += measurement.totalTurn * (descriptor.side == 0 ? 10 : 12)
        score += startHeadingError * 150
        score += endHeadingError * 120

        if descriptor.side == 0 {
            score += context.turnDemand * 130
            score += context.arrivalDemand * 30
        } else {
            score += context.directness * 90
            if descriptor.side != context.preferredSide {
                score += max(context.turnDemand, 0.45) * 200
            }
        }

        switch descriptor.family {
        case "turn":
            score += (1 - context.turnDemand) * 55
        case "brake":
            score += (1 - context.arrivalDemand) * 40
        case "orbit":
            score += context.directness * 70
        case "direct":
            score += max(context.turnDemand - 0.12, 0) * 80
        default:
            break
        }

        if measurement.staysInBounds == false {
            score += 90
        }

        return score
    }

    private static func descriptors(for metrics: MotionMetrics, preferredSide: Int) -> [MotionDescriptor] {
        let orbitScale = 0.82 + (metrics.farFactor * 0.26)
        let turnaroundScale = 0.90 + (metrics.farFactor * 0.30)
        let brakingScale = 0.74 + (metrics.farFactor * 0.24)

        return [
            MotionDescriptor(
                id: "direct-tight",
                family: "direct",
                side: 0,
                startReachScale: 0.90,
                endReachScale: 0.86,
                startLineWeight: 1.12,
                endLineWeight: 1.04,
                startHeadingWeight: 0.18,
                endHeadingWeight: 0.20,
                startNormalScale: 0.02,
                endNormalScale: 0.02,
                startGuideNormalBias: 0,
                endGuideNormalBias: 0,
                startFlowWeight: 0.02,
                endFlowWeight: 0.02,
                flowShift: -0.02,
                arcScale: 0.16,
                scoreBias: 18
            ),
            MotionDescriptor(
                id: "direct-soft",
                family: "direct",
                side: 0,
                startReachScale: 0.98,
                endReachScale: 0.94,
                startLineWeight: 1.04,
                endLineWeight: 0.96,
                startHeadingWeight: 0.22,
                endHeadingWeight: 0.28,
                startNormalScale: 0.04,
                endNormalScale: 0.08,
                startGuideNormalBias: 0,
                endGuideNormalBias: 0.04,
                startFlowWeight: 0.04,
                endFlowWeight: 0.08,
                flowShift: 0.02,
                arcScale: 0.24,
                scoreBias: 24
            ),
            MotionDescriptor(
                id: "turn-primary-tight",
                family: "turn",
                side: preferredSide,
                startReachScale: 1.26,
                endReachScale: 1.30,
                startLineWeight: -0.24,
                endLineWeight: -0.04,
                startHeadingWeight: 1.50,
                endHeadingWeight: 1.18,
                startNormalScale: 0.46,
                endNormalScale: 0.08,
                startGuideNormalBias: 0.30,
                endGuideNormalBias: 0.16,
                startFlowWeight: -0.30,
                endFlowWeight: 0.20,
                flowShift: -0.08,
                arcScale: turnaroundScale,
                scoreBias: 40
            ),
            MotionDescriptor(
                id: "turn-primary-wide",
                family: "turn",
                side: preferredSide,
                startReachScale: 1.30,
                endReachScale: 1.36,
                startLineWeight: -0.28,
                endLineWeight: -0.10,
                startHeadingWeight: 1.54,
                endHeadingWeight: 1.24,
                startNormalScale: 0.58,
                endNormalScale: 0.12,
                startGuideNormalBias: 0.34,
                endGuideNormalBias: 0.20,
                startFlowWeight: -0.34,
                endFlowWeight: 0.24,
                flowShift: 0.06,
                arcScale: turnaroundScale * 1.06,
                scoreBias: 46
            ),
            MotionDescriptor(
                id: "brake-primary-tight",
                family: "brake",
                side: preferredSide,
                startReachScale: 0.92,
                endReachScale: 1.42,
                startLineWeight: 0.50,
                endLineWeight: -0.20,
                startHeadingWeight: 0.70,
                endHeadingWeight: 1.52,
                startNormalScale: 0.16,
                endNormalScale: 0.20,
                startGuideNormalBias: 0.10,
                endGuideNormalBias: 0.26,
                startFlowWeight: 0.10,
                endFlowWeight: 0.32,
                flowShift: -0.04,
                arcScale: brakingScale,
                scoreBias: 44
            ),
            MotionDescriptor(
                id: "brake-primary-wide",
                family: "brake",
                side: preferredSide,
                startReachScale: 0.98,
                endReachScale: 1.50,
                startLineWeight: 0.44,
                endLineWeight: -0.26,
                startHeadingWeight: 0.74,
                endHeadingWeight: 1.62,
                startNormalScale: 0.22,
                endNormalScale: 0.26,
                startGuideNormalBias: 0.12,
                endGuideNormalBias: 0.32,
                startFlowWeight: 0.14,
                endFlowWeight: 0.38,
                flowShift: 0.04,
                arcScale: brakingScale * 1.04,
                scoreBias: 50
            ),
            MotionDescriptor(
                id: "orbit-primary-tight",
                family: "orbit",
                side: preferredSide,
                startReachScale: 0.90,
                endReachScale: 0.98,
                startLineWeight: 0.72,
                endLineWeight: 0.76,
                startHeadingWeight: 0.30,
                endHeadingWeight: 0.22,
                startNormalScale: 0.90,
                endNormalScale: 0.82,
                startGuideNormalBias: 0.16,
                endGuideNormalBias: 0.06,
                startFlowWeight: 0.26,
                endFlowWeight: 0.12,
                flowShift: -0.06,
                arcScale: orbitScale,
                scoreBias: 54
            ),
            MotionDescriptor(
                id: "orbit-primary-wide",
                family: "orbit",
                side: preferredSide,
                startReachScale: 0.94,
                endReachScale: 1.02,
                startLineWeight: 0.68,
                endLineWeight: 0.82,
                startHeadingWeight: 0.28,
                endHeadingWeight: 0.22,
                startNormalScale: 1.02,
                endNormalScale: 0.94,
                startGuideNormalBias: 0.18,
                endGuideNormalBias: 0.08,
                startFlowWeight: 0.30,
                endFlowWeight: 0.16,
                flowShift: 0.06,
                arcScale: orbitScale * 1.06,
                scoreBias: 60
            ),
            MotionDescriptor(
                id: "turn-secondary",
                family: "turn",
                side: -preferredSide,
                startReachScale: 1.18,
                endReachScale: 1.26,
                startLineWeight: -0.18,
                endLineWeight: 0.02,
                startHeadingWeight: 1.32,
                endHeadingWeight: 1.08,
                startNormalScale: 0.34,
                endNormalScale: 0.06,
                startGuideNormalBias: 0.22,
                endGuideNormalBias: 0.14,
                startFlowWeight: -0.20,
                endFlowWeight: 0.14,
                flowShift: 0.02,
                arcScale: turnaroundScale * 0.92,
                scoreBias: 88
            ),
            MotionDescriptor(
                id: "brake-secondary",
                family: "brake",
                side: -preferredSide,
                startReachScale: 0.90,
                endReachScale: 1.34,
                startLineWeight: 0.52,
                endLineWeight: -0.16,
                startHeadingWeight: 0.62,
                endHeadingWeight: 1.40,
                startNormalScale: 0.12,
                endNormalScale: 0.18,
                startGuideNormalBias: 0.08,
                endGuideNormalBias: 0.20,
                startFlowWeight: 0.10,
                endFlowWeight: 0.28,
                flowShift: -0.02,
                arcScale: brakingScale * 0.92,
                scoreBias: 96
            ),
        ]
    }

    private static func preferredTurnSide(
        metrics: MotionMetrics,
        startForward: CGVector,
        endForward: CGVector
    ) -> Int {
        let startDelta = signedAngle(from: startForward, to: metrics.direction)
        if abs(startDelta) > 0.16 {
            return startDelta > 0 ? 1 : -1
        }

        let endDelta = signedAngle(from: metrics.direction, to: endForward)
        if abs(endDelta) > 0.18 {
            return endDelta > 0 ? -1 : 1
        }

        if abs(metrics.dy) > abs(metrics.dx) * 0.72 {
            return metrics.dy > 0 ? -1 : 1
        }

        return metrics.dx >= 0 ? 1 : -1
    }

    private static func resolvedGuide(
        line: CGVector,
        forward: CGVector,
        normal: CGVector,
        sideSign: CGFloat,
        lineWeight: CGFloat,
        headingWeight: CGFloat,
        normalBias: CGFloat
    ) -> CGVector {
        normalizedOrDefault(
            line.scaled(by: lineWeight)
                + forward.scaled(by: headingWeight)
                + normal.scaled(by: normalBias * sideSign)
        )
    }

    private static func normalizedOrDefault(_ vector: CGVector) -> CGVector {
        let length = max(vector.length, normalizationEpsilon)
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private static func signedAngle(from lhs: CGVector, to rhs: CGVector) -> CGFloat {
        atan2((lhs.dx * rhs.dy) - (lhs.dy * rhs.dx), (lhs.dx * rhs.dx) + (lhs.dy * rhs.dy))
    }

    private struct MotionScoringContext {
        let metrics: MotionMetrics
        let startForward: CGVector
        let endForward: CGVector
        let preferredSide: Int

        var turnDemand: CGFloat {
            min(abs(HeadingDrivenCursorMotionModel.signedAngle(from: startForward, to: metrics.direction)) / .pi, 1)
        }

        var arrivalDemand: CGFloat {
            min(abs(HeadingDrivenCursorMotionModel.signedAngle(from: metrics.direction, to: endForward)) / .pi, 1)
        }

        var directness: CGFloat {
            (1 - max(turnDemand, arrivalDemand * 0.82)).clamped(to: 0...1)
        }
    }

    private struct MotionDescriptor {
        let id: String
        let family: String
        let side: Int
        let startReachScale: CGFloat
        let endReachScale: CGFloat
        let startLineWeight: CGFloat
        let endLineWeight: CGFloat
        let startHeadingWeight: CGFloat
        let endHeadingWeight: CGFloat
        let startNormalScale: CGFloat
        let endNormalScale: CGFloat
        let startGuideNormalBias: CGFloat
        let endGuideNormalBias: CGFloat
        let startFlowWeight: CGFloat
        let endFlowWeight: CGFloat
        let flowShift: CGFloat
        let arcScale: CGFloat
        let scoreBias: CGFloat

        var kind: CursorMotionKind {
            family == "direct" ? .base : .arched
        }
    }

    private struct MotionMetrics {
        let start: CGPoint
        let end: CGPoint
        let dx: CGFloat
        let dy: CGFloat
        let distance: CGFloat
        let direction: CGVector
        let normal: CGVector
        let horizontalFactor: CGFloat
        let verticalFactor: CGFloat
        let diagonalFactor: CGFloat
        let closeFactor: CGFloat
        let farFactor: CGFloat

        init(start: CGPoint, end: CGPoint) {
            self.start = start
            self.end = end
            dx = end.x - start.x
            dy = end.y - start.y
            distance = max(hypot(dx, dy), 1)
            direction = HeadingDrivenCursorMotionModel.normalizedOrDefault(CGVector(dx: dx, dy: dy))
            normal = HeadingDrivenCursorMotionModel.normalizedOrDefault(CGVector(dx: -direction.dy, dy: direction.dx))
            horizontalFactor = abs(dx) / distance
            verticalFactor = abs(dy) / distance
            diagonalFactor = min(horizontalFactor, verticalFactor) * 2
            closeFactor = (1 - (distance / 280)).clamped(to: 0...1)
            farFactor = ((distance - 180) / 540).clamped(to: 0...1)
        }
    }
}

struct CursorVisualSpringConfiguration: Equatable {
    let response: CGFloat
    let dampingFraction: CGFloat
    let stiffness: CGFloat
    let drag: CGFloat
    let dt: CGFloat
    let idleVelocityThreshold: CGFloat

    init(
        response: CGFloat,
        dampingFraction: CGFloat,
        dt: CGFloat = 1.0 / 240.0,
        idleVelocityThreshold: CGFloat = 28_800
    ) {
        let rawStiffness = response > 0 ? pow((2 * .pi) / response, 2) : .infinity

        self.response = response
        self.dampingFraction = dampingFraction
        self.dt = dt
        self.idleVelocityThreshold = idleVelocityThreshold
        stiffness = min(rawStiffness, idleVelocityThreshold)
        drag = 2 * dampingFraction * sqrt(stiffness)
    }
}

struct CursorVisualDynamicsConfiguration: Equatable {
    let tipSpring: CursorVisualSpringConfiguration
    let angleSpring: CursorVisualSpringConfiguration
    let headingVelocityFloor: CGFloat
    let animatedAngleOffsetMax: CGFloat
    let visibleTurnLeanMax: CGFloat
    let bodyOffsetScale: CGFloat
    let bodyOffsetMax: CGFloat
    let bodyLateralScale: CGFloat
    let bodyLateralMax: CGFloat
    let fogOffsetScale: CGFloat
    let fogOffsetMax: CGFloat
    let fogOpacityBase: CGFloat
    let fogOpacityVelocityScale: CGFloat
    let fogScaleVelocityScale: CGFloat
    let fogScaleMaxDelta: CGFloat

    static let officialInspired = CursorVisualDynamicsConfiguration(
        tipSpring: CursorVisualSpringConfiguration(response: 0.18, dampingFraction: 0.76),
        angleSpring: CursorVisualSpringConfiguration(response: 0.24, dampingFraction: 0.82),
        headingVelocityFloor: 14,
        animatedAngleOffsetMax: 0.28,
        visibleTurnLeanMax: 0.085,
        bodyOffsetScale: 0.0012,
        bodyOffsetMax: 2.4,
        bodyLateralScale: 0.06,
        bodyLateralMax: 1.4,
        fogOffsetScale: 0.0045,
        fogOffsetMax: 9,
        fogOpacityBase: 0.12,
        fogOpacityVelocityScale: 0.00006,
        fogScaleVelocityScale: 0.00012,
        fogScaleMaxDelta: 0.22
    )
}

struct CursorVisualDynamicsState: Equatable {
    var time: CGFloat
    var tipPosition: CGPoint
    var tipVelocity: CGVector
    var tipForce: CGVector
    var angle: CGFloat
    var angleVelocity: CGFloat
    var angleForce: CGFloat

    init(
        time: CGFloat = 0,
        tipPosition: CGPoint,
        tipVelocity: CGVector = .zero,
        tipForce: CGVector = .zero,
        angle: CGFloat = 0,
        angleVelocity: CGFloat = 0,
        angleForce: CGFloat = 0
    ) {
        self.time = time
        self.tipPosition = tipPosition
        self.tipVelocity = tipVelocity
        self.tipForce = tipForce
        self.angle = angle
        self.angleVelocity = angleVelocity
        self.angleForce = angleForce
    }
}

struct CursorVisualRenderState: Equatable {
    let tipPosition: CGPoint
    let rotation: CGFloat
    let visibleRotationOffset: CGFloat
    let cursorBodyOffset: CGVector
    let fogOffset: CGVector
    let fogOpacity: CGFloat
    let fogScale: CGFloat
}

enum CursorVisualDynamicsAnimator {
    static func state(at tipPosition: CGPoint, time: CGFloat = 0) -> CursorVisualDynamicsState {
        CursorVisualDynamicsState(time: time, tipPosition: tipPosition)
    }

    static func advance(
        state: CursorVisualDynamicsState,
        targetTipPosition: CGPoint,
        targetTime: CGFloat,
        idleAngleOffset: CGFloat = 0,
        baseHeading: CGFloat,
        configuration: CursorVisualDynamicsConfiguration = .officialInspired
    ) -> (state: CursorVisualDynamicsState, renderState: CursorVisualRenderState) {
        var adjustedState = state

        if (targetTime - adjustedState.time) > 1 {
            adjustedState.time = targetTime - (1.0 / 60.0)
        }

        while adjustedState.time < targetTime {
            adjustedState = advanceStep(
                state: adjustedState,
                targetTipPosition: targetTipPosition,
                idleAngleOffset: idleAngleOffset,
                baseHeading: baseHeading,
                configuration: configuration
            )
        }

        return (
            adjustedState,
            renderState(
                state: adjustedState,
                idleAngleOffset: idleAngleOffset,
                baseHeading: baseHeading,
                configuration: configuration
            )
        )
    }

    private static func advanceStep(
        state: CursorVisualDynamicsState,
        targetTipPosition: CGPoint,
        idleAngleOffset: CGFloat,
        baseHeading: CGFloat,
        configuration: CursorVisualDynamicsConfiguration
    ) -> CursorVisualDynamicsState {
        let dt = configuration.tipSpring.dt
        let halfDT = dt * 0.5

        let tipVelocityHalf = state.tipVelocity + state.tipForce.scaled(by: halfDT)
        let nextTipPosition = state.tipPosition + tipVelocityHalf.scaled(by: dt)
        let tipDisplacement = targetTipPosition - nextTipPosition
        let tipForce = tipDisplacement.scaled(by: configuration.tipSpring.stiffness)
            + tipVelocityHalf.scaled(by: -configuration.tipSpring.drag)
        let tipVelocity = tipVelocityHalf + tipForce.scaled(by: halfDT)

        let targetAngle = resolvedTargetAngle(
            velocity: tipVelocity,
            idleAngleOffset: idleAngleOffset,
            baseHeading: baseHeading,
            configuration: configuration
        )
        let angleVelocityHalf = state.angleVelocity + (state.angleForce * halfDT)
        let nextAngle = normalizeAngle(state.angle + (angleVelocityHalf * dt))
        let angleError = normalizeAngle(targetAngle - nextAngle)
        let angleForce = (angleError * configuration.angleSpring.stiffness)
            + ((-configuration.angleSpring.drag) * angleVelocityHalf)
        let angleVelocity = angleVelocityHalf + (angleForce * halfDT)

        return CursorVisualDynamicsState(
            time: state.time + dt,
            tipPosition: nextTipPosition,
            tipVelocity: tipVelocity,
            tipForce: tipForce,
            angle: normalizeAngle(nextAngle),
            angleVelocity: angleVelocity,
            angleForce: angleForce
        )
    }

    private static func renderState(
        state: CursorVisualDynamicsState,
        idleAngleOffset: CGFloat,
        baseHeading: CGFloat,
        configuration: CursorVisualDynamicsConfiguration
    ) -> CursorVisualRenderState {
        let speed = state.tipVelocity.length
        let direction = speed > 0.001
            ? state.tipVelocity.normalized
            : CGVector(dx: cos(baseHeading + idleAngleOffset), dy: sin(baseHeading + idleAngleOffset))
        let bodyBackward = direction.scaled(
            by: -min(speed * configuration.bodyOffsetScale, configuration.bodyOffsetMax)
        )
        let lateralAmount = CGFloat.clamped(
            state.angleVelocity * configuration.bodyLateralScale,
            lower: -configuration.bodyLateralMax,
            upper: configuration.bodyLateralMax
        )
        let bodyLateral = direction.perpendicular.scaled(by: lateralAmount)
        let cursorBodyOffset = bodyBackward + bodyLateral
        let fogOffset = direction.scaled(
            by: -min(speed * configuration.fogOffsetScale, configuration.fogOffsetMax)
        ) + bodyLateral.scaled(by: 0.6)
        let fogOpacity = min(
            configuration.fogOpacityBase + (speed * configuration.fogOpacityVelocityScale),
            0.34
        )
        let fogScale = 1 + min(
            speed * configuration.fogScaleVelocityScale,
            configuration.fogScaleMaxDelta
        )
        let visibleRotationOffset: CGFloat
        if speed > configuration.headingVelocityFloor {
            visibleRotationOffset = CGFloat.clamped(
                (lateralAmount / max(configuration.bodyLateralMax, 0.001)) * configuration.visibleTurnLeanMax,
                lower: -configuration.visibleTurnLeanMax,
                upper: configuration.visibleTurnLeanMax
            )
        } else {
            visibleRotationOffset = idleAngleOffset
        }

        return CursorVisualRenderState(
            tipPosition: state.tipPosition,
            rotation: normalizeAngle(
                state.angle + idleAngleOffset.clamped(
                    to: -configuration.animatedAngleOffsetMax...configuration.animatedAngleOffsetMax
                )
            ),
            visibleRotationOffset: visibleRotationOffset,
            cursorBodyOffset: cursorBodyOffset,
            fogOffset: fogOffset,
            fogOpacity: fogOpacity,
            fogScale: fogScale
        )
    }

    private static func resolvedTargetAngle(
        velocity: CGVector,
        idleAngleOffset: CGFloat,
        baseHeading: CGFloat,
        configuration: CursorVisualDynamicsConfiguration
    ) -> CGFloat {
        let speed = velocity.length
        guard speed > configuration.headingVelocityFloor else {
            return 0
        }

        let heading = atan2(velocity.dy, velocity.dx)
        return normalizeAngle(heading - baseHeading)
    }

    private static func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var value = angle
        while value > .pi {
            value -= 2 * .pi
        }
        while value < -.pi {
            value += 2 * .pi
        }
        return value
    }
}

struct CursorMotionState: Equatable {
    let point: CGPoint
    let rotation: CGFloat
    let displayRotation: CGFloat
    let cursorBodyOffset: CGVector
    let fogOffset: CGVector
    let fogOpacity: CGFloat
    let fogScale: CGFloat
    let trailProgress: CGFloat
    let isSettled: Bool
}

private enum CursorMotionPhase {
    case moving
    case idle(restingTipPosition: CGPoint)
}

final class CursorMotionSimulator {
    private static let baseHeading = CursorGlyphCalibration.neutralHeading + CursorGlyphCalibration.restingRotation

    private(set) var parameters: CursorMotionParameters
    private(set) var path: CursorMotionPath
    private(set) var start: CGPoint
    private(set) var end: CGPoint

    private var measurement: CursorMotionMeasurement
    private var phase: CursorMotionPhase
    private var progress: CGFloat
    private var progressSpringState: CursorMotionSpringState
    private var moveElapsed: CGFloat
    private var travelDuration: CGFloat
    private var visualState: CursorVisualDynamicsState
    private var time: CGFloat
    private var idlePhase: CGFloat

    init(start: CGPoint, end: CGPoint, parameters: CursorMotionParameters) {
        self.parameters = parameters
        path = CursorMotionPath(start: start, end: end)
        self.start = start
        self.end = end
        measurement = path.measure(bounds: nil)
        phase = .idle(restingTipPosition: start)
        progress = 1
        progressSpringState = CursorMotionSpringState()
        moveElapsed = 0
        travelDuration = OfficialCursorMotionModel.calibratedTravelDuration(
            distance: distanceBetween(start, end),
            measurement: measurement
        )
        visualState = CursorVisualDynamicsAnimator.state(at: start)
        time = 0
        idlePhase = 0
    }

    @discardableResult
    func snap(to point: CGPoint, path newPath: CursorMotionPath? = nil) -> CursorMotionState {
        if let newPath {
            path = newPath
            start = newPath.start
            end = newPath.end
            measurement = newPath.measure(bounds: nil)
        }

        time = 0
        idlePhase = 0
        moveElapsed = 0
        progress = 1
        progressSpringState = CursorMotionSpringState()
        visualState = CursorVisualDynamicsAnimator.state(at: point, time: time)
        phase = .idle(restingTipPosition: point)
        return renderCurrentState(trailProgress: 1, isSettled: true)
    }

    func begin(path: CursorMotionPath, measurement: CursorMotionMeasurement) {
        self.path = path
        start = path.start
        end = path.end
        self.measurement = measurement
        progress = 0
        progressSpringState = CursorMotionSpringState()
        moveElapsed = 0
        idlePhase = 0
        travelDuration = OfficialCursorMotionModel.calibratedTravelDuration(
            distance: distanceBetween(path.start, path.end),
            measurement: measurement
        )
        phase = .moving

        if visualState.tipPosition == .zero && path.start != .zero {
            visualState = CursorVisualDynamicsAnimator.state(at: path.start, time: time)
        }
    }

    func step(deltaTime dt: CGFloat) -> CursorMotionState {
        let clampedDelta = max(1.0 / 240.0, min(dt, 1.0 / 24.0))
        time += clampedDelta

        switch phase {
        case .moving:
            moveElapsed += clampedDelta
            let normalizedElapsed = (moveElapsed / max(travelDuration, 0.001)).clamped(to: 0...1)
            let springTime = normalizedElapsed * OfficialCursorMotionModel.closeEnoughTime
            (progress, progressSpringState) = CursorMotionProgressAnimator.advance(
                current: progress,
                state: progressSpringState,
                to: springTime
            )

            let sample = path.sample(at: progress)
            let renderState = advanceVisualDynamics(toward: sample.point)
            let finished = normalizedElapsed >= 1 || CursorMotionProgressAnimator.isCloseEnough(progress: progress)

            if finished {
                progress = 1
                phase = .idle(restingTipPosition: end)
                let settledState = advanceVisualDynamics(toward: end)
                return makeMotionState(renderState: settledState, trailProgress: 1, isSettled: true)
            }

            return makeMotionState(
                renderState: renderState,
                trailProgress: progress.clamped(to: 0...1),
                isSettled: false
            )

        case let .idle(restingTipPosition):
            idlePhase += clampedDelta * 3
            let idleAngleOffset = sin(idlePhase * 0.8) * SynthesizedCursorIdleStyle.wobbleAmplitude
            let renderState = advanceVisualDynamics(
                toward: restingTipPosition,
                idleAngleOffset: idleAngleOffset
            )
            return makeMotionState(renderState: renderState, trailProgress: 1, isSettled: true)
        }
    }

    private func advanceVisualDynamics(
        toward targetTipPosition: CGPoint,
        idleAngleOffset: CGFloat = 0
    ) -> CursorVisualRenderState {
        let result = CursorVisualDynamicsAnimator.advance(
            state: visualState,
            targetTipPosition: targetTipPosition,
            targetTime: time,
            idleAngleOffset: idleAngleOffset,
            baseHeading: Self.baseHeading
        )
        visualState = result.state
        return result.renderState
    }

    private func renderCurrentState(trailProgress: CGFloat, isSettled: Bool) -> CursorMotionState {
        let renderState = CursorVisualDynamicsAnimator.advance(
            state: visualState,
            targetTipPosition: visualState.tipPosition,
            targetTime: time,
            baseHeading: Self.baseHeading
        ).renderState
        return makeMotionState(renderState: renderState, trailProgress: trailProgress, isSettled: isSettled)
    }

    private func makeMotionState(
        renderState: CursorVisualRenderState,
        trailProgress: CGFloat,
        isSettled: Bool
    ) -> CursorMotionState {
        CursorMotionState(
            point: renderState.tipPosition,
            rotation: CursorGlyphCalibration.restingRotation + renderState.rotation,
            displayRotation: CursorGlyphCalibration.restingRotation + renderState.visibleRotationOffset,
            cursorBodyOffset: renderState.cursorBodyOffset,
            fogOffset: renderState.fogOffset,
            fogOpacity: renderState.fogOpacity,
            fogScale: renderState.fogScale,
            trailProgress: trailProgress,
            isSettled: isSettled
        )
    }
}

private func sampleCubic(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
    let omt = 1 - t
    let omt2 = omt * omt
    let t2 = t * t

    return CGPoint(
        x: (omt2 * omt * start.x)
            + (3 * omt2 * t * control1.x)
            + (3 * omt * t2 * control2.x)
            + (t2 * t * end.x),
        y: (omt2 * omt * start.y)
            + (3 * omt2 * t * control1.y)
            + (3 * omt * t2 * control2.y)
            + (t2 * t * end.y)
    )
}

private func sampleCubicTangent(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, t: CGFloat) -> CGVector {
    let omt = 1 - t
    return CGVector(
        dx: (3 * omt * omt * (control1.x - start.x))
            + (6 * omt * t * (control2.x - control1.x))
            + (3 * t * t * (end.x - control2.x)),
        dy: (3 * omt * omt * (control1.y - start.y))
            + (6 * omt * t * (control2.y - control1.y))
            + (3 * t * t * (end.y - control2.y))
    )
}

private func distanceBetween(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    hypot(rhs.x - lhs.x, rhs.y - lhs.y)
}

private extension CGRect {
    func contains(_ point: CGPoint, padding: CGFloat) -> Bool {
        insetBy(dx: -padding, dy: -padding).contains(point)
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x - rhs.dx, y: lhs.y - rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }
}

private extension CGVector {
    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
    }

    var length: CGFloat {
        hypot(dx, dy)
    }

    var normalized: CGVector {
        let resolvedLength = max(length, 0.001)
        return CGVector(dx: dx / resolvedLength, dy: dy / resolvedLength)
    }

    var perpendicular: CGVector {
        CGVector(dx: -dy, dy: dx)
    }

    func scaled(by factor: CGFloat) -> CGVector {
        CGVector(dx: dx * factor, dy: dy * factor)
    }
}

extension CGFloat {
    static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }

    var cursorIdentifier: String {
        String(format: "%.2f", Double(self))
    }

    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
