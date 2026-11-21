import AppKit

/// Uma faixa do mixer: número, nome do registro, pan e reverb (knobs),
/// fader de volume, nome do timbre, Mute e Solo.
final class ChannelStripView: PanelView {

    let index: Int

    var onSelect: ((Int) -> Void)?
    var onVolume: ((Int, Double) -> Void)?
    var onPan: ((Int, Double) -> Void)?
    var onReverb: ((Int, Double) -> Void)?
    var onMute: ((Int, Bool) -> Void)?
    var onSolo: ((Int, Bool) -> Void)?
    var onLearn: ((MapTarget) -> Void)?

    private let numberLabel = Theme.label("", size: 16, bold: true, color: Theme.cyan)
    private let titleLabel = Theme.label("", size: 9, bold: true, color: Theme.textDim)
    private let panCaption = Theme.label("PAN", size: 9, bold: true, color: Theme.textDim)
    private let reverbCaption = Theme.label("REVERB", size: 9, bold: true, color: Theme.textDim)
    private let nameLabel = Theme.label("vazio", size: 10, color: Theme.textDim)
    private let valueLabel = Theme.label("80%", size: 10, color: Theme.text)
    private let panKnob = KnobView()
    private let reverbKnob = KnobView()
    private let fader = FaderView()
    private let muteButton = ToggleButton(title: "M")
    private let soloButton = ToggleButton(title: "S")

    var isSelected = false {
        didSet {
            strokeColor = isSelected ? Theme.accent : Theme.panelLight
            strokeWidth = isSelected ? 2 : 1
        }
    }

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    private func knobColumn(_ caption: NSTextField, _ knob: KnobView) -> NSStackView {
        caption.alignment = .center
        knob.translatesAutoresizingMaskIntoConstraints = false
        knob.widthAnchor.constraint(equalToConstant: 32).isActive = true
        knob.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let column = NSStackView(views: [caption, knob])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 2
        return column
    }

    private func build() {
        numberLabel.stringValue = "\(index + 1)"
        numberLabel.alignment = .center
        titleLabel.alignment = .center
        nameLabel.alignment = .center
        valueLabel.alignment = .center

        panKnob.isBipolar = true
        panKnob.value = 0.5
        panKnob.defaultValue = 0.5
        reverbKnob.isBipolar = false
        reverbKnob.value = 0
        reverbKnob.defaultValue = 0

        let knobsRow = NSStackView(views: [knobColumn(panCaption, panKnob), knobColumn(reverbCaption, reverbKnob)])
        knobsRow.orientation = .horizontal
        knobsRow.alignment = .top
        knobsRow.spacing = 8

        fader.translatesAutoresizingMaskIntoConstraints = false
        fader.widthAnchor.constraint(equalToConstant: 56).isActive = true
        fader.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        fader.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .vertical)

        for label in [titleLabel, nameLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 92).isActive = true
        }

        muteButton.isToggle = true
        muteButton.onColor = Theme.warn
        muteButton.onTextColor = Theme.dark
        muteButton.preferredSize = NSSize(width: 38, height: 24)
        soloButton.isToggle = true
        soloButton.onColor = Theme.cyan
        soloButton.onTextColor = Theme.dark
        soloButton.preferredSize = NSSize(width: 38, height: 24)

        let buttonRow = NSStackView(views: [muteButton, soloButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 6

        let stack = NSStackView(views: [numberLabel, titleLabel, knobsRow, fader, valueLabel, nameLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Controles normais
        fader.onChange = { [weak self] value in
            guard let self = self else { return }
            self.valueLabel.stringValue = "\(Int((value * 100).rounded()))%"
            self.onSelect?(self.index)
            self.onVolume?(self.index, value)
        }
        panKnob.onChange = { [weak self] value in
            guard let self = self else { return }
            self.onSelect?(self.index)
            self.onPan?(self.index, value * 2 - 1)
        }
        reverbKnob.onChange = { [weak self] value in
            guard let self = self else { return }
            self.onSelect?(self.index)
            self.onReverb?(self.index, value)
        }
        muteButton.onToggle = { [weak self] on in
            guard let self = self else { return }
            self.onSelect?(self.index)
            self.onMute?(self.index, on)
        }
        soloButton.onToggle = { [weak self] on in
            guard let self = self else { return }
            self.onSelect?(self.index)
            self.onSolo?(self.index, on)
        }

        // Cliques no modo MIDI Learn
        fader.onLearnClick = { [weak self] in self?.learnClicked(.volume) }
        panKnob.onLearnClick = { [weak self] in self?.learnClicked(.pan) }
        reverbKnob.onLearnClick = { [weak self] in self?.learnClicked(.reverb) }
        muteButton.onLearnClick = { [weak self] in self?.learnClicked(.mute) }
        soloButton.onLearnClick = { [weak self] in self?.learnClicked(.solo) }
    }

    private enum Kind { case volume, pan, reverb, mute, solo }

    private func learnClicked(_ kind: Kind) {
        onSelect?(index)
        switch kind {
        case .volume: onLearn?(.volume(index))
        case .pan: onLearn?(.pan(index))
        case .reverb: onLearn?(.reverb(index))
        case .mute: onLearn?(.mute(index))
        case .solo: onLearn?(.solo(index))
        }
    }

    func applyLearnStates(_ provider: (MapTarget) -> LearnState) {
        fader.learnState = provider(.volume(index))
        panKnob.learnState = provider(.pan(index))
        reverbKnob.learnState = provider(.reverb(index))
        muteButton.learnState = provider(.mute(index))
        soloButton.learnState = provider(.solo(index))
    }

    func update(from layer: LayerState) {
        fader.value = layer.volume
        valueLabel.stringValue = "\(Int((layer.volume * 100).rounded()))%"
        panKnob.value = (layer.pan + 1) / 2
        reverbKnob.value = layer.reverb
        muteButton.isOn = layer.muted
        soloButton.isOn = layer.soloed
        titleLabel.stringValue = layer.title ?? ""
        if layer.sf2Path == nil {
            nameLabel.stringValue = "vazio"
            nameLabel.toolTip = nil
        } else {
            nameLabel.stringValue = layer.presetName
            nameLabel.toolTip = layer.presetName
        }
    }
}
