import AppKit

/// Teclado virtual desenhado em Core Graphics/AppKit.
/// Aceita mouse (clique e arrastar) e o teclado do computador (A W S E D F T G Y H U J K O L P).
final class PianoKeyboardView: NSView {

    /// Primeira nota visível (múltiplo de 12 = sempre um Dó).
    var firstNote: Int = 36 {
        didSet {
            releaseAll()
            needsDisplay = true
        }
    }
    let noteCount = 61   // 5 oitavas + 1 (Dó a Dó)

    var onNoteOn: ((UInt8, UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?

    private var litNotes = Set<Int>()
    private var mouseNote: Int?
    private var keyboardNotes: [UInt16: Int] = [:]   // keyCode → nota

    private static let blackSemitones: Set<Int> = [1, 3, 6, 8, 10]
    private static let keyMap: [String: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7,
        "y": 8, "h": 9, "u": 10, "j": 11, "k": 12, "o": 13, "l": 14, "p": 15
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func resignFirstResponder() -> Bool {
        releaseAll()
        return true
    }

    // MARK: - Geometria

    private var lastNote: Int { return firstNote + noteCount - 1 }

    private func isBlack(_ note: Int) -> Bool {
        return PianoKeyboardView.blackSemitones.contains(note % 12)
    }

    private var whiteKeyCount: Int {
        var count = 0
        for note in firstNote...lastNote where !isBlack(note) { count += 1 }
        return count
    }

    private func whitesBefore(_ note: Int) -> Int {
        var count = 0
        if note > firstNote {
            for n in firstNote..<note where !isBlack(n) { count += 1 }
        }
        return count
    }

    private func rect(for note: Int) -> NSRect {
        let whiteWidth = bounds.width / CGFloat(max(1, whiteKeyCount))
        let height = bounds.height
        let index = CGFloat(whitesBefore(note))
        if isBlack(note) {
            let blackWidth = whiteWidth * 0.62
            return NSRect(x: index * whiteWidth - blackWidth / 2,
                          y: height * 0.38,
                          width: blackWidth,
                          height: height * 0.62)
        }
        return NSRect(x: index * whiteWidth, y: 0, width: whiteWidth, height: height)
    }

    private func note(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        for n in firstNote...lastNote where isBlack(n) {
            if rect(for: n).contains(point) { return n }
        }
        for n in firstNote...lastNote where !isBlack(n) {
            if rect(for: n).contains(point) { return n }
        }
        return nil
    }

    private func velocity(at point: NSPoint) -> Int {
        // Mais perto da base da tecla = mais forte.
        let ratio = 1.0 - min(1.0, max(0.0, point.y / max(1, bounds.height)))
        return 45 + Int(ratio * 82)
    }

    // MARK: - Desenho

    override func draw(_ dirtyRect: NSRect) {
        Theme.dark.setFill()
        bounds.fill()

        let accent = Theme.accent
        let whiteLit = accent.blended(withFraction: 0.35, of: .white) ?? accent

        for note in firstNote...lastNote where !isBlack(note) {
            let r = rect(for: note).insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            (litNotes.contains(note) ? whiteLit : Theme.text).setFill()
            path.fill()
            Theme.silverDim.setStroke()
            path.lineWidth = 1
            path.stroke()

            if note % 12 == 0 {
                let label = "C\(note / 12 - 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.darkGray
                ]
                label.draw(at: NSPoint(x: r.minX + 4, y: 6), withAttributes: attributes)
            }
        }

        for note in firstNote...lastNote where isBlack(note) {
            let r = rect(for: note)
            let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            (litNotes.contains(note) ? accent : Theme.rgb(0x08141F)).setFill()
            path.fill()
        }
    }

    // MARK: - Estado visual / disparo

    func setNote(_ note: Int, active: Bool) {
        if active { litNotes.insert(note) } else { litNotes.remove(note) }
        needsDisplay = true
    }

    func clearVisual() {
        litNotes.removeAll()
        needsDisplay = true
    }

    private func trigger(_ note: Int, on: Bool, velocity: Int = 96) {
        guard note >= 0, note <= 127 else { return }
        setNote(note, active: on)
        if on {
            onNoteOn?(UInt8(note), UInt8(max(1, min(127, velocity))))
        } else {
            onNoteOff?(UInt8(note))
        }
    }

    /// Solta tudo que o usuário está segurando (mouse e teclado do computador).
    func releaseAll() {
        if let held = mouseNote {
            trigger(held, on: false)
            mouseNote = nil
        }
        for (_, note) in keyboardNotes {
            trigger(note, on: false)
        }
        keyboardNotes.removeAll()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let n = note(at: point) else { return }
        mouseNote = n
        trigger(n, on: true, velocity: velocity(at: point))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let n = note(at: point)
        if n != mouseNote {
            if let old = mouseNote { trigger(old, on: false) }
            mouseNote = n
            if let new = n { trigger(new, on: true, velocity: velocity(at: point)) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let held = mouseNote {
            trigger(held, on: false)
            mouseNote = nil
        }
    }

    // MARK: - Teclado do computador

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        guard !event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers?.lowercased(),
              let semitone = PianoKeyboardView.keyMap[chars],
              keyboardNotes[event.keyCode] == nil else {
            super.keyDown(with: event)
            return
        }
        let note = firstNote + 12 + semitone
        guard note <= 127 else { return }
        keyboardNotes[event.keyCode] = note
        trigger(note, on: true, velocity: 96)
    }

    override func keyUp(with event: NSEvent) {
        if let note = keyboardNotes.removeValue(forKey: event.keyCode) {
            trigger(note, on: false)
        } else {
            super.keyUp(with: event)
        }
    }
}
