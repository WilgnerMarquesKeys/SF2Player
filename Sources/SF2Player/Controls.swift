import AppKit

// MARK: - Fader vertical

final class FaderView: NSView {
    var value: Double = 0.8 {
        didSet { if value != oldValue { needsDisplay = true } }
    }
    var defaultValue: Double = 0.8
    var onChange: ((Double) -> Void)?

    private let knobSize = NSSize(width: 34, height: 20)

    override var acceptsFirstResponder: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    private var travelLow: CGFloat { return knobSize.height / 2 + 2 }
    private var travelHigh: CGFloat { return bounds.height - knobSize.height / 2 - 2 }

    override func draw(_ dirtyRect: NSRect) {
        let low = travelLow
        let high = travelHigh
        let cx = bounds.midX

        // marcações da escala
        Theme.textDim.withAlphaComponent(0.45).setStroke()
        for i in 0...10 {
            let y = low + CGFloat(i) / 10 * (high - low)
            let length: CGFloat = (i % 5 == 0) ? 7 : 4
            let left = NSBezierPath()
            left.move(to: NSPoint(x: cx - 15 - length, y: y))
            left.line(to: NSPoint(x: cx - 15, y: y))
            left.lineWidth = 1
            left.stroke()
            let right = NSBezierPath()
            right.move(to: NSPoint(x: cx + 15, y: y))
            right.line(to: NSPoint(x: cx + 15 + length, y: y))
            right.lineWidth = 1
            right.stroke()
        }

        // trilho
        let track = NSRect(x: cx - 3, y: low, width: 6, height: max(1, high - low))
        Theme.dark.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()

        // parte preenchida
        let y = low + CGFloat(value) * (high - low)
        let fill = NSRect(x: cx - 3, y: low, width: 6, height: max(0, y - low))
        Theme.accent.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()

        // botão do fader
        let knob = NSRect(x: cx - knobSize.width / 2, y: y - knobSize.height / 2,
                          width: knobSize.width, height: knobSize.height)
        let path = NSBezierPath(roundedRect: knob, xRadius: 5, yRadius: 5)
        let gradient = NSGradient(starting: Theme.rgb(0xE3EDF3), ending: Theme.rgb(0x8FA2B2))
        gradient?.draw(in: path, angle: -90)
        Theme.dark.setStroke()
        path.lineWidth = 1
        path.stroke()
        Theme.accent.setFill()
        NSRect(x: knob.minX + 6, y: knob.midY - 1, width: knob.width - 12, height: 2).fill()
    }

    private func update(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let span = max(1, travelHigh - travelLow)
        let raw = Double((point.y - travelLow) / span)
        let clamped = min(1, max(0, raw))
        value = clamped
        onChange?(clamped)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            value = defaultValue
            onChange?(defaultValue)
            return
        }
        update(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        update(from: event)
    }
}

// MARK: - Knob rotativo

final class KnobView: NSView {
    var value: Double = 0.5 {
        didSet { if value != oldValue { needsDisplay = true } }
    }
    var defaultValue: Double = 0.5
    var isBipolar = false { didSet { needsDisplay = true } }
    var onChange: ((Double) -> Void)?

    private var dragStartY: CGFloat = 0
    private var dragStartValue: Double = 0

    override var acceptsFirstResponder: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = side / 2 - 3

        // arco de fundo
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 225, endAngle: -45, clockwise: true)
        track.lineWidth = 3
        track.lineCapStyle = .round
        Theme.dark.setStroke()
        track.stroke()

        // arco ativo
        let angle: Double = 225.0 - value * 270.0
        let startAngle: Double = isBipolar ? 90.0 : 225.0
        if abs(angle - startAngle) > 0.5 {
            let active = NSBezierPath()
            let clockwise = isBipolar ? (value >= 0.5) : true
            active.appendArc(withCenter: center, radius: radius,
                             startAngle: CGFloat(startAngle), endAngle: CGFloat(angle), clockwise: clockwise)
            active.lineWidth = 3
            active.lineCapStyle = .round
            Theme.accent.setStroke()
            active.stroke()
        }

        // corpo do knob
        let bodyRadius = radius - 6
        let bodyRect = NSRect(x: center.x - bodyRadius, y: center.y - bodyRadius,
                              width: bodyRadius * 2, height: bodyRadius * 2)
        let body = NSBezierPath(ovalIn: bodyRect)
        let gradient = NSGradient(starting: Theme.rgb(0xE3EDF3), ending: Theme.rgb(0x8FA2B2))
        gradient?.draw(in: body, angle: -90)
        Theme.dark.setStroke()
        body.lineWidth = 1
        body.stroke()

        // ponteiro
        let radians = CGFloat(angle) * CGFloat.pi / 180
        let inner = bodyRadius * 0.25
        let outer = bodyRadius * 0.92
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner))
        pointer.line(to: NSPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
        pointer.lineWidth = 2.5
        pointer.lineCapStyle = .round
        Theme.accent.setStroke()
        pointer.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            value = defaultValue
            onChange?(defaultValue)
            return
        }
        dragStartY = event.locationInWindow.y
        dragStartValue = value
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = Double(event.locationInWindow.y - dragStartY) / 150.0
        let newValue = min(1, max(0, dragStartValue + delta))
        value = newValue
        onChange?(newValue)
    }
}

// MARK: - Botão (liga/desliga ou de ação)

final class ToggleButton: NSView {
    var title: String { didSet { needsDisplay = true } }
    var isToggle = false
    var isOn = false { didSet { needsDisplay = true } }
    var idleColor: NSColor = Theme.dark { didSet { needsDisplay = true } }
    var onColor: NSColor = Theme.accent { didSet { needsDisplay = true } }
    var textColor: NSColor = Theme.text { didSet { needsDisplay = true } }
    var onTextColor: NSColor = Theme.text { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 11 { didSet { needsDisplay = true } }
    var preferredSize = NSSize(width: 40, height: 24) {
        didSet { invalidateIntrinsicContentSize() }
    }
    var onToggle: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    private var pressed = false { didSet { needsDisplay = true } }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    override var intrinsicContentSize: NSSize { return preferredSize }
    override var acceptsFirstResponder: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        var base = isOn ? onColor : idleColor
        if pressed { base = base.blended(withFraction: 0.25, of: NSColor.white) ?? base }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        base.setFill()
        path.fill()
        Theme.silverDim.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: isOn ? onTextColor : textColor
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                  withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(point)
        pressed = false
        guard inside else { return }
        if isToggle {
            isOn = !isOn
            onToggle?(isOn)
        } else {
            onClick?()
        }
    }
}
