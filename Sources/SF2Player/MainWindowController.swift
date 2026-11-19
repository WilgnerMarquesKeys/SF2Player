import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Serviços
    private let audio = SamplerEngine()
    private let midi = MIDIManager()
    private let workQueue = DispatchQueue(label: "br.com.exemplo.sf2player.work", qos: .userInitiated)

    // MARK: - Estado
    private var presets: [SF2Preset] = []
    private var currentURL: URL?
    private var securityScopedURL: URL?
    private var requestCounter = 0
    private var isShutDown = false

    // MARK: - Interface
    private let openButton = NSButton(title: "Carregar SoundFont (.sf2)…", target: nil, action: nil)
    private let fileLabel = NSTextField(labelWithString: "Nenhum arquivo carregado")
    private let presetTitle = NSTextField(labelWithString: "Timbre:")
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let volumeTitle = NSTextField(labelWithString: "Volume master:")
    private let volumeSlider = NSSlider(value: 0.8, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeLabel = NSTextField(labelWithString: "80%")
    private let panicButton = NSButton(title: "Panic (All Notes Off)", target: nil, action: nil)
    private let octaveTitle = NSTextField(labelWithString: "Oitavas:")
    private let octaveDownButton = NSButton(title: "Oitava −", target: nil, action: nil)
    private let octaveUpButton = NSButton(title: "Oitava +", target: nil, action: nil)
    private let octaveLabel = NSTextField(labelWithString: "")
    private let midiLabel = NSTextField(labelWithString: "MIDI: procurando controladores…")
    private let statusLabel = NSTextField(labelWithString: "Carregue um arquivo .sf2 para começar.")
    private let hintLabel = NSTextField(labelWithString: "Dica: clique nas teclas ou use o teclado do computador (A W S E D F T G Y H U J K O L P).")
    private let keyboard = PianoKeyboardView()

    // MARK: - Inicialização

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 440),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "SF2Player"
        window.minSize = NSSize(width: 760, height: 380)
        window.center()
        super.init(window: window)
        window.delegate = self

        buildUI()
        wireEvents()
        startServices()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    func focusKeyboard() {
        window?.makeFirstResponder(keyboard)
    }

    func shutdown() {
        if isShutDown { return }
        isShutDown = true
        midi.stop()
        audio.stop()
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    func windowWillClose(_ notification: Notification) {
        shutdown()
    }

    // MARK: - Construção da interface

    private func makeRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10
        return row
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        presetPopup.addItem(withTitle: "(carregue um arquivo .sf2)")
        presetPopup.isEnabled = false
        presetPopup.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        presetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        volumeSlider.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        volumeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        volumeLabel.alignment = .right
        volumeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        panicButton.contentTintColor = NSColor.systemRed

        octaveLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        updateOctaveLabel()

        for label in [midiLabel, statusLabel, hintLabel] {
            label.textColor = NSColor.secondaryLabelColor
            label.font = NSFont.systemFont(ofSize: 11)
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)

        let fileRow = makeRow([openButton, fileLabel])
        let presetRow = makeRow([presetTitle, presetPopup])
        let volumeRow = makeRow([volumeTitle, volumeSlider, volumeLabel, panicButton])
        let octaveRow = makeRow([octaveTitle, octaveDownButton, octaveUpButton, octaveLabel])
        let bottomRow = makeRow([midiLabel, statusLabel])

        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 100), for: .vertical)
        keyboard.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        let rows: [NSView] = [fileRow, presetRow, volumeRow, octaveRow, keyboard, hintLabel, bottomRow]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func wireEvents() {
        openButton.target = self
        openButton.action = #selector(openSoundFont(_:))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        panicButton.target = self
        panicButton.action = #selector(panicAction(_:))
        octaveDownButton.target = self
        octaveDownButton.action = #selector(octaveDown(_:))
        octaveUpButton.target = self
        octaveUpButton.action = #selector(octaveUp(_:))

        // Mantém o foco no teclado virtual para o teclado do computador continuar funcionando.
        let controls: [NSControl] = [openButton, presetPopup, volumeSlider, panicButton,
                                     octaveDownButton, octaveUpButton]
        for control in controls { control.refusesFirstResponder = true }

        // Teclado virtual → áudio
        keyboard.onNoteOn = { [weak self] note, velocity in
            self?.audio.noteOn(note, velocity: velocity)
        }
        keyboard.onNoteOff = { [weak self] note in
            self?.audio.noteOff(note)
        }

        // MIDI físico → áudio (+ destaque visual no teclado)
        midi.onNoteOn = { [weak self] note, velocity in
            self?.audio.noteOn(note, velocity: velocity)
            DispatchQueue.main.async { self?.keyboard.setNote(Int(note), active: true) }
        }
        midi.onNoteOff = { [weak self] note in
            self?.audio.noteOff(note)
            DispatchQueue.main.async { self?.keyboard.setNote(Int(note), active: false) }
        }
        midi.onControlChange = { [weak self] controller, value in
            if controller == 0 || controller == 32 { return }   // ignora Bank Select
            self?.audio.controlChange(controller, value: value)
        }
        midi.onPitchBend = { [weak self] value in
            self?.audio.pitchBend(value)
        }
        midi.onDevicesChanged = { [weak self] names in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if names.isEmpty {
                    self.midiLabel.stringValue = "MIDI: nenhum controlador detectado (conecte um teclado USB)"
                } else {
                    self.midiLabel.stringValue = "MIDI: " + names.joined(separator: ", ")
                }
            }
        }
    }

    private func startServices() {
        audio.masterVolume = Float(volumeSlider.doubleValue)
        do {
            try audio.start()
        } catch {
            showError("Falha ao iniciar o áudio", detail: error.localizedDescription)
        }
        midi.start()
    }

    // MARK: - Ações

    @objc func openSoundFont(_ sender: Any?) {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.title = "Escolher SoundFont"
        panel.message = "Selecione um arquivo SoundFont (.sf2)"
        panel.prompt = "Abrir"
        panel.allowedFileTypes = ["sf2", "SF2"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadSoundFont(at: url)
        }
    }

    @objc func panicAction(_ sender: Any?) {
        keyboard.releaseAll()
        audio.panic()
        keyboard.clearVisual()
        setStatus("Panic: todas as notas foram silenciadas.")
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        applyPreset(at: sender.indexOfSelectedItem)
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        audio.masterVolume = Float(sender.doubleValue)
        volumeLabel.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
    }

    @objc private func octaveDown(_ sender: Any?) { shiftOctave(by: -12) }
    @objc private func octaveUp(_ sender: Any?) { shiftOctave(by: 12) }

    private func shiftOctave(by delta: Int) {
        let newFirst = keyboard.firstNote + delta
        guard newFirst >= 0, newFirst + keyboard.noteCount - 1 <= 127 else { return }
        keyboard.firstNote = newFirst
        updateOctaveLabel()
    }

    private func updateOctaveLabel() {
        let first = keyboard.firstNote / 12 - 1
        let last = (keyboard.firstNote + keyboard.noteCount - 1) / 12 - 1
        octaveLabel.stringValue = "C\(first) – C\(last)"
    }

    // MARK: - Carregamento do SoundFont

    func loadSoundFont(at url: URL) {
        // Sandbox: URLs vindos do NSOpenPanel/Finder já têm acesso; isto é inofensivo nesses casos.
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = url.startAccessingSecurityScopedResource() ? url : nil

        setStatus("Lendo \(url.lastPathComponent)…")
        presetPopup.isEnabled = false

        workQueue.async { [weak self] in
            do {
                let file = try SF2Parser.parse(url: url)
                DispatchQueue.main.async {
                    self?.didParse(file, from: url)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.setStatus("Erro ao ler o arquivo.")
                    self?.showError("Não foi possível abrir o SoundFont", detail: error.localizedDescription)
                }
            }
        }
    }

    private func didParse(_ file: SF2File, from url: URL) {
        presets = file.presets
        currentURL = url

        var summary = "\(url.lastPathComponent) · \(file.presets.count) timbres"
        if let name = file.name { summary += " · “\(name)”" }
        fileLabel.stringValue = summary
        fileLabel.toolTip = url.path

        presetPopup.removeAllItems()
        var seenTitles = Set<String>()
        for (index, preset) in file.presets.enumerated() {
            var title = String(format: "[%03d:%03d]  %@", preset.bank, preset.program, preset.name)
            if seenTitles.contains(title) { title += " (\(index))" }   // addItem remove títulos duplicados
            seenTitles.insert(title)
            presetPopup.addItem(withTitle: title)
        }
        presetPopup.isEnabled = true

        let defaultIndex = file.presets.firstIndex(where: { $0.bank == 0 && $0.program == 0 }) ?? 0
        presetPopup.selectItem(at: defaultIndex)
        applyPreset(at: defaultIndex)
        focusKeyboard()
    }

    private func applyPreset(at index: Int) {
        guard index >= 0, index < presets.count, let url = currentURL else { return }
        let preset = presets[index]

        requestCounter += 1
        let myRequest = requestCounter
        setStatus("Carregando timbre “\(preset.name)”…")

        keyboard.releaseAll()
        audio.panic()
        keyboard.clearVisual()

        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.audio.start()
                try self.audio.loadPreset(from: url, bank: preset.bank, program: preset.program)
                DispatchQueue.main.async {
                    if myRequest == self.requestCounter {
                        self.setStatus("Pronto: \(preset.name)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if myRequest == self.requestCounter {
                        self.setStatus("Erro ao carregar o timbre.")
                        self.showError("Não foi possível carregar o timbre “\(preset.name)”",
                                       detail: error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - Auxiliares

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
