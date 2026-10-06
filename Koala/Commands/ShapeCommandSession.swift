//
//  ShapeCommandSession.swift
//  Koala
//

import CoreGraphics
import Foundation
import Observation

@Observable
final class ShapeCommandSession {
    var isActive = false
    var category: ToolCategory = .line
    var lineVariant: LineVariant = .line
    var circleVariant: CircleVariant = .center
    var rectangleVariant: RectangleVariant = .center
    var attachedStrokeID: UUID?
    var controlPoints: [CGPoint] = []
    var inputText = ""
    var lastError: String?
    var persistentClose = false
    var revision = 0
    var arcSweepRadians: CGFloat?

    var isRefiningAttachedStroke: Bool {
        attachedStrokeID != nil
    }

    var previewPoints: [CGPoint] {
        guard canFinish else { return controlPoints }
        return ShapeGeometry.previewPoints(
            controlPoints: controlPoints,
            category: category,
            lineVariant: lineVariant,
            circleVariant: circleVariant,
            rectangleVariant: rectangleVariant,
            arcSweepRadians: arcSweepRadians
        )
    }

    var displayControlPoints: [CGPoint] {
        controlPoints
    }

    var toolTitle: String {
        switch category {
        case .line:
            switch lineVariant {
            case .line: return "Line"
            case .arc: return "Arc"
            case .constructionLine: return "Construction Line"
            }
        case .circle:
            switch circleVariant {
            case .center: return "Circle"
            case .edge: return "Circle (Edge)"
            case .ellipse: return "Ellipse"
            }
        case .rectangle:
            return "Rectangle"
        default:
            return category.label
        }
    }

    var prompt: String {
        let index = controlPoints.count
        switch category {
        case .line:
            switch lineVariant {
            case .line, .constructionLine:
                return index == 0 ? "Start point:" : "End point:"
            case .arc:
                switch index {
                case 0: return "Center point:"
                case 1: return "Start of arc:"
                default: return "Drag to finish arc"
                }
            }
        case .circle:
            switch circleVariant {
            case .center:
                return index == 0 ? "Center point:" : "Radius (or d100 for diameter):"
            case .edge:
                return index == 0 ? "First edge point:" : "Second edge point:"
            case .ellipse:
                switch index {
                case 0: return "Center point:"
                case 1: return "Horizontal radius (rx):"
                default: return "Vertical radius (ry):"
                }
            }
        case .rectangle:
            switch rectangleVariant {
            case .center:
                switch index {
                case 0: return "Center point:"
                case 1: return "Half-width distance:"
                default: return "Half-height distance:"
                }
            case .edge:
                return index == 0 ? "First corner:" : "Opposite corner:"
            }
        default:
            return "Point:"
        }
    }

    var requiredPoints: Int {
        ShapeGeometry.requiredControlPoints(
            category: category,
            lineVariant: lineVariant,
            circleVariant: circleVariant,
            rectangleVariant: rectangleVariant
        )
    }

    var canFinish: Bool {
        controlPoints.count >= requiredPoints
    }

    func start(
        category: ToolCategory,
        lineVariant: LineVariant = .line,
        circleVariant: CircleVariant = .center,
        rectangleVariant: RectangleVariant = .center
    ) {
        self.category = category
        self.lineVariant = lineVariant
        self.circleVariant = circleVariant
        self.rectangleVariant = rectangleVariant
        isActive = true
        attachedStrokeID = nil
        controlPoints = []
        arcSweepRadians = nil
        inputText = ""
        lastError = nil
        revision += 1
    }

    func attachCommittedStroke(
        id: UUID,
        category: ToolCategory,
        lineVariant: LineVariant = .line,
        circleVariant: CircleVariant = .center,
        rectangleVariant: RectangleVariant = .center,
        controlPoints: [CGPoint]
    ) {
        self.category = category
        self.lineVariant = lineVariant
        self.circleVariant = circleVariant
        self.rectangleVariant = rectangleVariant
        isActive = true
        attachedStrokeID = id
        self.controlPoints = controlPoints
        arcSweepRadians = nil
        inputText = ""
        lastError = nil
        revision += 1
    }

    func cancel() {
        isActive = false
        attachedStrokeID = nil
        controlPoints = []
        arcSweepRadians = nil
        inputText = ""
        lastError = nil
        revision += 1
    }

    func addPoint(_ point: CGPoint) {
        guard isActive else { return }
        guard controlPoints.count < requiredPoints else { return }
        controlPoints.append(point)
        if lineVariant == .arc {
            arcSweepRadians = nil
        }
        inputText = ""
        lastError = nil
        revision += 1
    }

    func movePoint(at index: Int, to point: CGPoint) {
        guard controlPoints.indices.contains(index) else { return }
        controlPoints[index] = point
        if lineVariant == .arc {
            arcSweepRadians = nil
        }
        revision += 1
    }

    func setArcSweep(_ sweep: CGFloat?) {
        guard lineVariant == .arc else { return }
        arcSweepRadians = sweep
        revision += 1
    }

    func translateAllPoints(by delta: CGPoint) {
        guard !controlPoints.isEmpty else { return }
        controlPoints = controlPoints.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        revision += 1
    }

    @discardableResult
    func submit(
        units: MeasurementUnit = .points,
        grid: GridSettings? = nil,
        documentSettings: DocumentSettings? = nil,
        snapEnabled: Bool = false
    ) -> Bool {
        let raw = inputText
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

        if isRefiningAttachedStroke {
            return submitRefinementInput(
                raw,
                units: units,
                grid: grid,
                documentSettings: documentSettings,
                snapEnabled: snapEnabled
            )
        }

        if let scalarPoint = resolveScalarInput(raw, units: units) {
            addResolvedPoint(scalarPoint, grid: grid, documentSettings: documentSettings, snapEnabled: snapEnabled)
            CommandHistoryStore.shared.recordInput(raw)
            return true
        }

        switch CommandPointParser.parse(raw, hasStartPoint: !controlPoints.isEmpty) {
        case .success(let input):
            switch input {
            case .cancel:
                cancel()
                return true
            case .undo:
                guard !controlPoints.isEmpty else {
                    lastError = "Nothing to undo."
                    return false
                }
                controlPoints.removeLast()
                inputText = ""
                revision += 1
                return true
            case .close, .absolute, .relativePolar, .relativeCartesian:
                let resolved = resolveInput(input, units: units)
                guard let point = resolved else {
                    if case .close = input {
                        lastError = "Close not supported for this tool."
                        return false
                    }
                    lastError = CommandPointParseError.needsStartPoint.localizedDescription
                    return false
                }
                addResolvedPoint(point, grid: grid, documentSettings: documentSettings, snapEnabled: snapEnabled)
                CommandHistoryStore.shared.recordInput(raw)
                return true
            }
        case .failure(let error):
            lastError = error.localizedDescription
            return false
        }
    }

    private func addResolvedPoint(
        _ point: CGPoint,
        grid: GridSettings?,
        documentSettings: DocumentSettings?,
        snapEnabled: Bool
    ) {
        guard let grid, let documentSettings else {
            addPoint(point)
            return
        }
        let snapped = snapDrawingPoint(point, grid: grid, settings: documentSettings, enabled: snapEnabled)
        let projected = ShapeGeometry.projectCommandPoint(
            snapped,
            controlPoints: controlPoints,
            category: category,
            lineVariant: lineVariant,
            circleVariant: circleVariant,
            rectangleVariant: rectangleVariant
        )
        let final = snapDrawingControlPoint(
            raw: snapped,
            projected: projected,
            grid: grid,
            settings: documentSettings,
            enabled: snapEnabled
        )
        addPoint(final)
    }

    private func submitRefinementInput(
        _ raw: String,
        units: MeasurementUnit,
        grid: GridSettings?,
        documentSettings: DocumentSettings?,
        snapEnabled: Bool
    ) -> Bool {
        if let scalarPoint = resolveRefinementScalarInput(raw, units: units) {
            replaceRefinementPoint(
                scalarPoint,
                grid: grid,
                documentSettings: documentSettings,
                snapEnabled: snapEnabled
            )
            CommandHistoryStore.shared.recordInput(raw)
            return true
        }

        switch CommandPointParser.parse(raw, hasStartPoint: !controlPoints.isEmpty) {
        case .success(let input):
            switch input {
            case .cancel:
                cancel()
                return true
            case .undo:
                lastError = "Undo is not available while refining."
                return false
            case .close:
                lastError = "Close is not supported while refining."
                return false
            case .absolute, .relativePolar, .relativeCartesian:
                guard let resolved = resolveInput(input, units: units) else {
                    lastError = CommandPointParseError.needsStartPoint.localizedDescription
                    return false
                }
                replaceRefinementPoint(
                    resolved,
                    grid: grid,
                    documentSettings: documentSettings,
                    snapEnabled: snapEnabled
                )
                CommandHistoryStore.shared.recordInput(raw)
                return true
            }
        case .failure(let error):
            lastError = error.localizedDescription
            return false
        }
    }

    private func resolveRefinementScalarInput(_ raw: String, units: MeasurementUnit) -> CGPoint? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !controlPoints.isEmpty else { return nil }

        if category == .circle, circleVariant == .center,
           let center = controlPoints.first {
            if let diameter = CommandPointParser.parseDiameter(trimmed) {
                let radius = units.toDocumentUnits(diameter) / 2
                return CGPoint(x: center.x + radius, y: center.y)
            }
            if let scalar = CommandPointParser.parseScalar(trimmed) {
                let radius = units.toDocumentUnits(scalar)
                return CGPoint(x: center.x + radius, y: center.y)
            }
        }

        if category == .circle, circleVariant == .ellipse,
           let scalar = CommandPointParser.parseScalar(trimmed),
           let center = controlPoints.first,
           controlPoints.count >= 3 {
            let value = units.toDocumentUnits(scalar)
            return CGPoint(x: center.x, y: center.y + value)
        }

        if category == .rectangle, rectangleVariant == .center,
           let scalar = CommandPointParser.parseScalar(trimmed),
           let center = controlPoints.first,
           controlPoints.count >= 3 {
            let value = units.toDocumentUnits(scalar)
            return CGPoint(x: center.x, y: center.y + value)
        }

        return nil
    }

    private func replaceRefinementPoint(
        _ point: CGPoint,
        grid: GridSettings?,
        documentSettings: DocumentSettings?,
        snapEnabled: Bool
    ) {
        guard !controlPoints.isEmpty else { return }

        if let grid, let documentSettings {
            let snapped = snapDrawingPoint(point, grid: grid, settings: documentSettings, enabled: snapEnabled)
            let prefix = Array(controlPoints.dropLast())
            let projected = ShapeGeometry.projectCommandPoint(
                snapped,
                controlPoints: prefix,
                category: category,
                lineVariant: lineVariant,
                circleVariant: circleVariant,
                rectangleVariant: rectangleVariant
            )
            controlPoints[controlPoints.count - 1] = snapDrawingControlPoint(
                raw: snapped,
                projected: projected,
                grid: grid,
                settings: documentSettings,
                enabled: snapEnabled
            )
        } else {
            controlPoints[controlPoints.count - 1] = point
        }

        inputText = ""
        lastError = nil
        revision += 1
    }

    private func resolveScalarInput(_ raw: String, units: MeasurementUnit) -> CGPoint? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !controlPoints.isEmpty else { return nil }

        if category == .circle, circleVariant == .center, controlPoints.count == 1 {
            if let diameter = CommandPointParser.parseDiameter(trimmed) {
                let radius = units.toDocumentUnits(diameter) / 2
                return CommandPointParser.polarOffset(from: controlPoints[0], distance: radius, degrees: 0)
            }
            if let scalar = CommandPointParser.parseScalar(trimmed) {
                let radius = units.toDocumentUnits(scalar)
                return CommandPointParser.polarOffset(from: controlPoints[0], distance: radius, degrees: 0)
            }
        }

        if category == .circle, circleVariant == .ellipse {
            if let scalar = CommandPointParser.parseScalar(trimmed) {
                let value = units.toDocumentUnits(scalar)
                let center = controlPoints[0]
                if controlPoints.count == 1 {
                    return CGPoint(x: center.x + value, y: center.y)
                }
                if controlPoints.count == 2 {
                    return CGPoint(x: center.x, y: center.y + value)
                }
            }
        }

        if category == .rectangle, rectangleVariant == .center {
            if let scalar = CommandPointParser.parseScalar(trimmed) {
                let value = units.toDocumentUnits(scalar)
                let center = controlPoints[0]
                if controlPoints.count == 1 {
                    return CGPoint(x: center.x + value, y: center.y)
                }
                if controlPoints.count == 2 {
                    return CGPoint(x: center.x, y: center.y + value)
                }
            }
        }

        return nil
    }

    private func resolveInput(_ input: CommandPointInput, units: MeasurementUnit) -> CGPoint? {
        switch input {
        case .absolute(let point):
            let docPoint = CGPoint(
                x: units.toDocumentUnits(point.x),
                y: units.toDocumentUnits(point.y)
            )
            if category == .circle, circleVariant == .center, controlPoints.count == 1 {
                let radius = units.toDocumentUnits(abs(point.x))
                return CommandPointParser.polarOffset(from: controlPoints[0], distance: radius, degrees: 0)
            }
            return docPoint
        case .relativePolar(let distance, let degrees):
            guard let previous = controlPoints.last else { return nil }
            let docDistance = units.toDocumentUnits(distance)
            return CommandPointParser.polarOffset(from: previous, distance: docDistance, degrees: degrees)
        case .relativeCartesian(let offset):
            guard let previous = controlPoints.last else { return nil }
            return CGPoint(
                x: previous.x + units.toDocumentUnits(offset.x),
                y: previous.y + units.toDocumentUnits(offset.y)
            )
        case .close, .undo, .cancel:
            return CommandPointParser.resolve(input, from: controlPoints.last)
        }
    }

    func buildStroke(
        layerID: UUID,
        strokeWidth: CGFloat,
        strokeColor: CodableColor,
        cornerRadius: CGFloat = 0
    ) -> VectorStroke? {
        guard canFinish else { return nil }
        return ShapeGeometry.buildStroke(
            controlPoints: controlPoints,
            category: category,
            lineVariant: lineVariant,
            circleVariant: circleVariant,
            rectangleVariant: rectangleVariant,
            layerID: layerID,
            strokeWidth: strokeWidth,
            strokeColor: strokeColor,
            closed: persistentClose,
            cornerRadius: cornerRadius,
            arcSweepRadians: arcSweepRadians
        )
    }

    func finish() {
        isActive = false
        attachedStrokeID = nil
        controlPoints = []
        arcSweepRadians = nil
        inputText = ""
        lastError = nil
        revision += 1
    }

    /// Restarts the session for the next chained line segment, keeping the last point as the start.
    func restartLineChain(anchor: CGPoint) {
        let savedCategory = category
        let savedLineVariant = lineVariant
        let savedCircleVariant = circleVariant
        let savedRectangleVariant = rectangleVariant
        start(
            category: savedCategory,
            lineVariant: savedLineVariant,
            circleVariant: savedCircleVariant,
            rectangleVariant: savedRectangleVariant
        )
        addPoint(anchor)
    }
}
