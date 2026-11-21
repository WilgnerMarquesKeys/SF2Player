import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {

    // MARK: - Serviços
    private let layerCount = 8
    private let audio = MultiSamplerEngine(layerCount: 8)
    private let midi = MIDIManager()
    private let workQueue = DispatchQueue(label: "br.com.exemplo.sf2player.work", qos: .userInitiated)

    // MARK: - Estado
    private var state = PerformanceState.empty(layerCount: 8)
    private var selected = 0
    private var parsedFiles: [Int: SF2File] = [:]
    private var loadedKeys = [String](repeating: "", count: 8)
    private var loadTokens = [Int](repeating: 0, count: 8)
    private var currentMemory = 1
    private var isShutDown = false

    // MARK: - Interface: topo
    private var memoryButtons: [ToggleButton] = []
    private let saveButton = ToggleButton(title: "Salvar")

    // MARK: - Interface: mixer
    private var strips: [ChannelStripView] = []
    private let masterFader = FaderView()
    private let gainKnob = KnobView()
    private let masterValueLabel = Theme.label("80%", size: 10)
    private let gainValueLabel = Theme.label("+0.0 dB", size: 10)
    private let panicButton = ToggleButton(title: "PANIC")

    // MARK: - Interface: painel da camada selecionada
    private let detailTitle = Theme.label("CAMADA 1", size: 10, bold: true, color: Theme.cyan)
    private let loadButton = ToggleButton(title: "Carregar .sf2…")
    private let fileLabel = Theme.label("nenhum arquivo", size: 11, color: Theme.textDim)
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lowLabel = Theme.label("C-1", size: 12, bold: true)
    private let highLabel = Theme.label("G9", size: 12, bold: true)
    private let lowStepper = NSStepper()
    private let highStepper = NSStepper()
    private let channelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let transposeLabel = Theme.label("0 st", size: 12, bold: true)
    private let transposeStepper = NSStepper()
    private let reverbKnob = KnobView()
    private let reverbLabel = Theme.label("0%", size: 11)

    // MARK: - Interface: rodapé
    private let keyboard = PianoKeyboardView()
    private let octaveDownButton = ToggleButton(title: "Oitava −")
    private let octaveUpButton = ToggleButton(title: "Oitava +")
    private let octaveLabel = Theme.label("", size: 11, color: Theme.textDim)
    private let midiLabel = Theme.label("MIDI: procurando controladores…", size: 11, color: Theme.textDim)
    private let statusLabel = Theme.label("Escolha uma camada e carregue um arquivo .sf2.", size: 11, color: Theme.textDim)

    // MARK: - Inicialização

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "SF2Player"
        window.minSize = NSSize(width: 1080, height: 680)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = BackgroundView()
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
        PerformanceStore.save(state, key: "session.last")
        midi.stop()
        audio.stop()
    }

    func windowWillClose(_ notification: Notification) {
        shutdown()
    }

    // MARK: - Construção da interface

    private func vstack(_ views: [NSView], spacing: CGFloat = 4, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    private func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func column(_ caption: String, _ content: NSView) -> NSStackView {
        let title = Theme.label(caption.uppercased(), size: 9, bold: true, color: Theme.textDim)
        return vstack([title, content], spacing: 4)
    }

    private func fixWidth(_ view: NSView, _ width: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // ---------- Barra superior ----------
        let titleLabel = Theme.label("SF2Player", size: 24, bold: true, color: Theme.cyan)
        let subtitle = Theme.label("Mixer de SoundFonts multicamadas", size: 11, color: Theme.textDim)
        let titleStack = vstack([titleLabel, subtitle], spacing: 0)

        var memoryViews: [NSView] = [Theme.label("MEMÓRIA", size: 10, bold: true, color: Theme.textDim)]
        for n in 1...4 {
            let button = ToggleButton(title: "\(n)")
            button.preferredSize = NSSize(width: 34, height: 26)
            button.fontSize = 12
            button.onClick = { [weak self] in self?.recallMemory(n) }
            memoryButtons.append(button)
            memoryViews.append(button)
        }
        saveButton.preferredSize = NSSize(width: 70, height: 26)
        saveButton.onClick = { [weak self] in self?.saveMemory() }
        memoryViews.append(saveButton)
        let memoryRow = hstack(memoryViews, spacing: 6)

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        let topBar = hstack([titleStack, topSpacer, memoryRow], spacing: 12)

        // ---------- Mixer: 8 camadas + master ----------
        for index in 0..<layerCount {
            let strip = ChannelStripView(index: index)
            strip.onSelect = { [weak self] i in self?.selectLayer(i) }
            strip.onVolume = { [weak self] i, v in self?.layerVolumeChanged(i, v) }
            strip.onPan = { [weak self] i, p in self?.layerPanChanged(i, p) }
            strip.onMute = { [weak self] i, on in self?.layerMuteChanged(i, on) }
            strip.onSolo = { [weak self] i, on in self?.layerSoloChanged(i, on) }
            strips.append(strip)
        }
        strips[0].isSelected = true

        let masterPanel = makeMasterPanel()
        var stripViews: [NSView] = strips
        stripViews.append(masterPanel)
        let stripsRow = NSStackView(views: stripViews)
        stripsRow.orientation = .horizontal
        stripsRow.distribution = .fillEqually
        stripsRow.spacing = 8
        for view in stripViews {
            view.heightAnchor.constraint(equalTo: stripsRow.heightAnchor).isActive = true
        }

        // ---------- Painel da camada selecionada ----------
        let detail = PanelView()
        detail.fillColor = Theme.panelMid
        detail.cornerRadius = 10

        fixWidth(fileLabel, 150)
        loadButton.preferredSize = NSSize(width: 150, height: 26)
        let soundColumn = vstack([detailTitle, loadButton, fileLabel], spacing: 4)

        fixWidth(presetPopup, 240)
        presetPopup.addItem(withTitle: "(carregue um arquivo .sf2)")
        presetPopup.isEnabled = false
        let presetColumn = column("Timbre", presetPopup)

        configure(stepper: lowStepper, min: 0, max: 127, action: #selector(lowChanged(_:)))
        configure(stepper: highStepper, min: 0, max: 127, action: #selector(highChanged(_:)))
        fixWidth(lowLabel, 34)
        fixWidth(highLabel, 34)
        let rangeRow = hstack([Theme.label("de", size: 11, color: Theme.textDim), lowLabel, lowStepper,
                               Theme.label("até", size: 11, color: Theme.textDim), highLabel, highStepper], spacing: 4)
        let rangeColumn = column("Teclas", rangeRow)

        channelPopup.addItems(withTitles: ["Omni"] + (1...16).map { "Canal \($0)" })
        channelPopup.target = self
        channelPopup.action = #selector(channelChanged(_:))
        channelPopup.refusesFirstResponder = true
        fixWidth(channelPopup, 90)
        let channelColumn = column("Canal MIDI", channelPopup)

        configure(stepper: transposeStepper, min: -24, max: 24, action: #selector(transposeChanged(_:)))
        fixWidth(transposeLabel, 44)
        let transposeColumn = column("Transposição", hstack([transposeLabel, transposeStepper], spacing: 4))

        reverbKnob.translatesAutoresizingMaskIntoConstraints = false
        reverbKnob.widthAnchor.constraint(equalToConstant: 34).isActive = true
        reverbKnob.heightAnchor.constraint(equalToConstant: 34).isActive = true
        reverbKnob.defaultValue = 0
        reverbKnob.value = 0
        fixWidth(reverbLabel, 36)
        let reverbColumn = column("Reverb", hstack([reverbKnob, reverbLabel], spacing: 4))

        let detailRow = NSStackView(views: [soundColumn, presetColumn, rangeColumn, channelColumn, transposeColumn, reverbColumn])
        detailRow.orientation = .horizontal
        detailRow.alignment = .top
        detailRow.spacing = 16
        detailRow.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        detailRow.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(detailRow)
        NSLayoutConstraint.activate([
            detailRow.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            detailRow.topAnchor.constraint(equalTo: detail.topAnchor),
            detailRow.bottomAnchor.constraint(equalTo: detail.bottomAnchor)
        ])

        // ---------- Rodapé ----------
        octaveDownButton.preferredSize = NSSize(width: 74, height: 22)
        octaveUpButton.preferredSize = NSSize(width: 74, height: 22)
        octaveDownButton.fontSize = 10
        octaveUpButton.fontSize = 10
        octaveDownButton.onClick = { [weak self] in self?.shiftOctave(by: -12) }
        octaveUpButton.onClick = { [weak self] in self?.shiftOctave(by: 12) }
        fixWidth(octaveLabel, 70)
        octaveLabel.alignment = .center
        updateOctaveLabel()

        midiLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        statusLabel.alignment = .right
        statusLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        let bottomRow = hstack([octaveDownButton, octaveLabel, octaveUpButton, midiLabel, statusLabel], spacing: 10)

        // ---------- Montagem ----------
        let rows: [NSView] = [topBar, stripsRow, detail, keyboard, bottomRow]
        let root = NSStackView(views: rows)
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
        for row in rows {
            row.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        stripsRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        stripsRow.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .vertical)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.heightAnchor.constraint(equalToConstant: 110).isActive = true
    }

    private func makeMasterPanel() -> PanelView {
        let panel = PanelView()
        panel.fillColor = Theme.panelMid

        let title = Theme.label("MASTER", size: 16, bold: true, color: Theme.cyan)
        title.alignment = .center
        let gainCaption = Theme.label("GANHO", size: 9, bold: true, color: Theme.textDim)
        gainCaption.alignment = .center

        gainKnob.isBipolar = false
        gainKnob.value = 0
        gainKnob.defaultValue = 0
        gainKnob.translatesAutoresizingMaskIntoConstraints = false
        gainKnob.widthAnchor.constraint(equalToConstant: 38).isActive = true
        gainKnob.heightAnchor.constraint(equalToConstant: 38).isActive = true

        masterFader.defaultValue = 0.8
        masterFader.translatesAutoresizingMaskIntoConstraints = false
        masterFader.widthAnchor.constraint(equalToConstant: 56).isActive = true
        masterFader.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        masterFader.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .vertical)

        masterValueLabel.alignment = .center
        gainValueLabel.alignment = .center

        panicButton.preferredSize = NSSize(width: 84, height: 24)
        panicButton.idleColor = Theme.danger
        panicButton.textColor = NSColor.white
        panicButton.onClick = { [weak self] in self?.panicAction(nil) }

        let stack = vstack([title, gainCaption, gainKnob, masterFader, masterValueLabel, gainValueLabel, panicButton],
                           spacing: 6, alignment: .centerX)
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        return panel
    }

    private func configure(stepper: NSStepper, min: Int, max: Int, action: Selector) {
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
        stepper.refusesFirstResponder = true
    }

    // MARK: - Ligações (eventos)

    private func wireEvents() {
        loadButton.onClick = { [weak self] in self?.openSoundFont(nil) }

        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        presetPopup.refusesFirstResponder = true

        reverbKnob.onChange = { [weak self] value in
            guard let self = self else { return }
            self.state.layers[self.selected].reverb = value
            self.reverbLabel.stringValue = "\(Int((value * 100).rounded()))%"
            self.audio.setReverb(Float(value), layer: self.selected)
        }

        masterFader.onChange = { [weak self] value in
            guard let self = self else { return }
            self.state.masterVolume = value
            self.audio.setMasterVolume(Float(value))
            self.updateMasterLabels()
        }
        gainKnob.onChange = { [weak self] value in
            guard let self = self else { return }
            self.state.masterGainDB = value * 9
            self.audio.setMasterGain(Float(self.state.masterGainDB))
            self.updateMasterLabels()
        }

        // Teclado virtual → áudio (canal 0 = ignora filtro de canal)
        keyboard.onNoteOn = { [weak self] note, velocity in
            self?.audio.noteOn(channel: 0, note: note, velocity: velocity)
        }
        keyboard.onNoteOff = { [weak self] note in
            self?.audio.noteOff(channel: 0, note: note)
        }

        // MIDI físico → áudio (+ destaque visual)
        midi.onNoteOn = { [weak self] channel, note, velocity in
            self?.audio.noteOn(channel: channel, note: note, velocity: velocity)
            DispatchQueue.main.async { self?.keyboard.setNote(Int(note), active: true) }
        }
        midi.onNoteOff = { [weak self] channel, note in
            self?.audio.noteOff(channel: channel, note: note)
            DispatchQueue.main.async { self?.keyboard.setNote(Int(note), active: false) }
        }
        midi.onControlChange = { [weak self] channel, controller, value in
            // Ignora Bank Select, Volume (7) e Pan (10): quem controla é o mixer.
            if controller == 0 || controller == 32 || controller == 7 || controller == 10 { return }
            self?.audio.controlChange(channel: channel, controller: controller, value: value)
        }
        midi.onPitchBend = { [weak self] channel, value in
            self?.audio.pitchBend(channel: channel, value: value)
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
        do {
            try audio.start()
        } catch {
            showError("Falha ao iniciar o áudio", detail: error.localizedDescription)
        }
        midi.start()

        updateMemoryButtons()
        if let last = PerformanceStore.load(key: "session.last") {
            applyState(last)
            setStatus("Última sessão restaurada.")
        } else {
            applyState(PerformanceState.empty(layerCount: layerCount))
        }
    }

    // MARK: - Aplicar estado completo (memórias / sessão)

    private func applyState(_ newState: PerformanceState) {
        var fresh = newState
        while fresh.layers.count < layerCount { fresh.layers.append(LayerState()) }
        if fresh.layers.count > layerCount { fresh.layers = Array(fresh.layers.prefix(layerCount)) }
        state = fresh

        for index in 0..<layerCount {
            pushLayerToEngine(index)
            strips[index].update(from: state.layers[index])
            loadSoundIfNeeded(index)
        }
        masterFader.value = state.masterVolume
        gainKnob.value = state.masterGainDB / 9
        audio.setMasterVolume(Float(state.masterVolume))
        audio.setMasterGain(Float(state.masterGainDB))
        updateMasterLabels()
        refreshDetail()
    }

    private func pushLayerToEngine(_ index: Int) {
        let layer = state.layers[index]
        audio.configure(layer: index, low: layer.lowNote, high: layer.highNote,
                        channel: layer.channel, transpose: layer.transpose)
        audio.setVolume(Float(layer.volume), layer: index)
        audio.setPan(Float(layer.pan), layer: index)
        audio.setMute(layer.muted, layer: index)
        audio.setSolo(layer.soloed, layer: index)
        audio.setReverb(Float(layer.reverb), layer: index)
    }

    // MARK: - Memórias 1–4

    private func updateMemoryButtons() {
        for (offset, button) in memoryButtons.enumerated() {
            button.isOn = (offset + 1 == currentMemory)
        }
    }

    private func recallMemory(_ number: Int) {
        currentMemory = number
        updateMemoryButtons()
        if let saved = PerformanceStore.load(key: "memory.\(number)") {
            keyboard.releaseAll()
            audio.panic()
            keyboard.clearVisual()
            applyState(saved)
            setStatus("Memória \(number) carregada.")
        } else {
            setStatus("Memória \(number) está vazia. Monte o som e clique em Salvar.")
        }
    }

    private func saveMemory() {
        PerformanceStore.save(state, key: "memory.\(currentMemory)")
        setStatus("Performance salva na memória \(currentMemory).")
    }

    // MARK: - Seleção de camada e painel de detalhes

    private func selectLayer(_ index: Int) {
        guard index != selected, index >= 0, index < layerCount else { return }
        selected = index
        for (offset, strip) in strips.enumerated() {
            strip.isSelected = (offset == index)
        }
        refreshDetail()
    }

    private func refreshDetail() {
        let layer = state.layers[selected]
        detailTitle.stringValue = "CAMADA \(selected + 1)"
        if let path = layer.sf2Path {
            fileLabel.stringValue = (path as NSString).lastPathComponent
            fileLabel.toolTip = path
        } else {
            fileLabel.stringValue = "nenhum arquivo"
            fileLabel.toolTip = nil
        }
        rebuildPresetPopup()

        lowStepper.integerValue = layer.lowNote
        lowLabel.stringValue = Theme.noteName(layer.lowNote)
        highStepper.integerValue = layer.highNote
        highLabel.stringValue = Theme.noteName(layer.highNote)
        channelPopup.selectItem(at: max(0, min(16, layer.channel)))
        transposeStepper.integerValue = layer.transpose
        transposeLabel.stringValue = transposeText(layer.transpose)
        reverbKnob.value = layer.reverb
        reverbLabel.stringValue = "\(Int((layer.reverb * 100).rounded()))%"
    }

    private func transposeText(_ value: Int) -> String {
        return value == 0 ? "0 st" : String(format: "%+d st", value)
    }

    private func rebuildPresetPopup() {
        presetPopup.removeAllItems()
        let layer = state.layers[selected]
        guard layer.sf2Path != nil, let file = parsedFiles[selected] else {
            presetPopup.addItem(withTitle: layer.sf2Path == nil ? "(carregue um arquivo .sf2)" : "(lendo arquivo…)")
            presetPopup.isEnabled = false
            return
        }
        var seen = Set<String>()
        var selectedIndex = 0
        for (offset, preset) in file.presets.enumerated() {
            var title = String(format: "[%03d:%03d]  %@", preset.bank, preset.program, preset.name)
            if seen.contains(title) { title += " (\(offset))" }   // addItem remove títulos repetidos
            seen.insert(title)
            presetPopup.addItem(withTitle: title)
            if preset.bank == layer.bank && preset.program == layer.program { selectedIndex = offset }
        }
        presetPopup.selectItem(at: selectedIndex)
        presetPopup.isEnabled = true
    }

    // MARK: - Ações do painel de detalhes

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        guard let file = parsedFiles[selected] else { return }
        let offset = sender.indexOfSelectedItem
        guard offset >= 0, offset < file.presets.count else { return }
        let preset = file.presets[offset]
        state.layers[selected].bank = preset.bank
        state.layers[selected].program = preset.program
        state.layers[selected].presetName = preset.name
        strips[selected].update(from: state.layers[selected])
        loadSoundIfNeeded(selected)
    }

    @objc private func lowChanged(_ sender: NSStepper) {
        var value = sender.integerValue
        let high = state.layers[selected].highNote
        if value > high { value = high; sender.integerValue = value }
        state.layers[selected].lowNote = value
        lowLabel.stringValue = Theme.noteName(value)
        pushLayerToEngine(selected)
    }

    @objc private func highChanged(_ sender: NSStepper) {
        var value = sender.integerValue
        let low = state.layers[selected].lowNote
        if value < low { value = low; sender.integerValue = value }
        state.layers[selected].highNote = value
        highLabel.stringValue = Theme.noteName(value)
        pushLayerToEngine(selected)
    }

    @objc private func channelChanged(_ sender: NSPopUpButton) {
        state.layers[selected].channel = sender.indexOfSelectedItem
        pushLayerToEngine(selected)
    }

    @objc private func transposeChanged(_ sender: NSStepper) {
        let value = sender.integerValue
        state.layers[selected].transpose = value
        transposeLabel.stringValue = transposeText(value)
        pushLayerToEngine(selected)
    }

    // MARK: - Ações do mixer

    private func layerVolumeChanged(_ index: Int, _ value: Double) {
        state.layers[index].volume = value
        audio.setVolume(Float(value), layer: index)
    }

    private func layerPanChanged(_ index: Int, _ value: Double) {
        state.layers[index].pan = value
        audio.setPan(Float(value), layer: index)
    }

    private func layerMuteChanged(_ index: Int, _ on: Bool) {
        state.layers[index].muted = on
        audio.setMute(on, layer: index)
    }

    private func layerSoloChanged(_ index: Int, _ on: Bool) {
        state.layers[index].soloed = on
        audio.setSolo(on, layer: index)
    }

    private func updateMasterLabels() {
        masterValueLabel.stringValue = "\(Int((state.masterVolume * 100).rounded()))%"
        gainValueLabel.stringValue = String(format: "+%.1f dB", state.masterGainDB)
    }

    @objc func panicAction(_ sender: Any?) {
        keyboard.releaseAll()
        audio.panic()
        keyboard.clearVisual()
        setStatus("Panic: todas as notas foram silenciadas.")
    }

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

    // MARK: - Carregar SoundFont na camada selecionada

    @objc func openSoundFont(_ sender: Any?) {
        guard let window = window else { return }
        let layerIndex = selected
        let panel = NSOpenPanel()
        panel.title = "Escolher SoundFont para a camada \(layerIndex + 1)"
        panel.message = "Selecione um arquivo SoundFont (.sf2)"
        panel.prompt = "Abrir"
        panel.allowedFileTypes = ["sf2", "SF2"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.assignSoundFont(url, toLayer: layerIndex)
        }
    }

    /// Usado pelo Finder ("Abrir com...") e pelo menu: carrega na camada selecionada.
    func loadSoundFont(at url: URL) {
        assignSoundFont(url, toLayer: selected)
    }

    private func assignSoundFont(_ url: URL, toLayer index: Int) {
        setStatus("Lendo \(url.lastPathComponent)…")
        workQueue.async { [weak self] in
            do {
                let file = try SF2Parser.parse(url: url)
                DispatchQueue.main.async {
                    self?.didParse(file, url: url, layer: index)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.setStatus("Erro ao ler o arquivo.")
                    self?.showError("Não foi possível abrir o SoundFont", detail: error.localizedDescription)
                }
            }
        }
    }

    private func didParse(_ file: SF2File, url: URL, layer index: Int) {
        parsedFiles[index] = file
        let preset = file.presets.first(where: { $0.bank == 0 && $0.program == 0 }) ?? file.presets[0]
        state.layers[index].sf2Path = url.path
        state.layers[index].bank = preset.bank
        state.layers[index].program = preset.program
        state.layers[index].presetName = preset.name
        loadedKeys[index] = ""   // força o carregamento
        strips[index].update(from: state.layers[index])
        if index == selected { refreshDetail() }
        loadSoundIfNeeded(index)
    }

    private func loadSoundIfNeeded(_ index: Int) {
        let layer = state.layers[index]
        guard let path = layer.sf2Path else {
            loadedKeys[index] = ""
            audio.clearSound(layer: index)
            return
        }
        let key = "\(path)|\(layer.bank)|\(layer.program)"
        if loadedKeys[index] == key { return }
        loadedKeys[index] = key
        loadTokens[index] += 1
        let token = loadTokens[index]
        let url = URL(fileURLWithPath: path)
        let bank = layer.bank
        let program = layer.program
        let presetName = layer.presetName

        setStatus("Carregando camada \(index + 1)…")
        workQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let file = try SF2Parser.parse(url: url)
                try self.audio.start()
                try self.audio.loadInstrument(layer: index, url: url, bank: bank, program: program)
                DispatchQueue.main.async {
                    guard token == self.loadTokens[index] else { return }
                    self.parsedFiles[index] = file
                    if index == self.selected { self.refreshDetail() }
                    self.setStatus("Camada \(index + 1) pronta: \(presetName)")
                }
            } catch {
                DispatchQueue.main.async {
                    guard token == self.loadTokens[index] else { return }
                    self.loadedKeys[index] = ""
                    if FileManager.default.fileExists(atPath: path) {
                        self.setStatus("Erro ao carregar a camada \(index + 1).")
                        self.showError("Não foi possível carregar a camada \(index + 1)",
                                       detail: error.localizedDescription)
                    } else {
                        self.setStatus("Arquivo não encontrado na camada \(index + 1): \((path as NSString).lastPathComponent)")
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
