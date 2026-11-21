import AppKit

/// Paleta azul inspirada na tela do StageLab (cores amostradas da imagem de referência).
enum Theme {
    static func rgb(_ value: UInt32) -> NSColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static let backgroundTop = Theme.rgb(0x0C1B30)
    static let backgroundBottom = Theme.rgb(0x16365D)
    static let panel = Theme.rgb(0x14345A)
    static let panelMid = Theme.rgb(0x1A3C66)
    static let panelLight = Theme.rgb(0x254A78)
    static let dark = Theme.rgb(0x0F2036)
    static let silver = Theme.rgb(0xA6BBC9)
    static let silverDim = Theme.rgb(0x6F879A)
    static let accent = Theme.rgb(0x2299ED)
    static let cyan = Theme.rgb(0x7ADEFB)
    static let text = Theme.rgb(0xF4F9FC)
    static let textDim = Theme.rgb(0x8FAEC0)
    static let danger = Theme.rgb(0xD8434B)
    static let warn = Theme.rgb(0xF2A93B)

    static func label(_ text: String, size: CGFloat = 12, bold: Bool = false, color: NSColor = Theme.text) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func noteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let safe = max(0, min(127, note))
        return "\(names[safe % 12])\(safe / 12 - 1)"
    }
}

/// Fundo da janela com degradê azul.
final class BackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(starting: Theme.backgroundTop, ending: Theme.backgroundBottom)
        gradient?.draw(in: bounds, angle: -90)
    }
}

/// Painel arredondado (base das faixas de canal e dos painéis).
class PanelView: NSView {
    var fillColor: NSColor = Theme.panel { didSet { needsDisplay = true } }
    var strokeColor: NSColor = Theme.panelLight { didSet { needsDisplay = true } }
    var strokeWidth: CGFloat = 1 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 12 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }
}

// MARK: - MIDI Learn (contorno nos controles)

enum LearnState {
    case off        // modo Learn desligado
    case available  // dá para mapear
    case mapped     // já tem um controle MIDI atribuído
    case armed      // esperando você mexer no controle do teclado
}

func drawLearnOutline(_ state: LearnState, in rect: NSRect, cornerRadius: CGFloat = 6) {
    var color = Theme.cyan
    var width: CGFloat = 1.5
    switch state {
    case .off:
        return
    case .available:
        color = Theme.textDim.withAlphaComponent(0.8)
    case .mapped:
        color = Theme.cyan
    case .armed:
        color = Theme.warn
        width = 3
    }
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2),
                            xRadius: cornerRadius, yRadius: cornerRadius)
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}
