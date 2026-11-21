import AppKit

/// Uma faixa do mixer: número, pan (knob), fader de volume, nome do timbre, Mute e Solo.
final class ChannelStripView: PanelView {

    let index: Int

    var onSelect: ((Int) -> Void)?
    var onVolume: ((Int, Double) -> Void)?
    var onPan: ((Int, Double) -> Void)?
    var onMute: ((Int, Bool) -> Void)?
    var onSolo: ((Int, Bool) -> Void)?

    private let numberLabel = Theme.label("", size: 16, bold: true, color: Theme.cyan)
    private let panCaption = Theme.label("PAN", size: 9, bold: true, color: Theme.textDim)
    private let nameLabel = Theme.label("vazio", size: 10, color: Theme.textDim)
    private let valueLabel = Theme.label("80%", size: 10, color: Theme.text)
    private let knob = KnobView()
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

    private func build() {
        numberLabel.stringValue = "\(index + 1)"
        numberLabel.alignment = .center
        panCaption.alignment = .center
        nameLabel.alignment = .center
        valueLabel.alignment = .center

        knob.isBipolar = true
        knob.value = 0.5
        knob.defaultValue = 0.5
        knob.translatesAutoresizingMaskIntoConstraints = false
        knob.widthAnchor.constraint(equalToConstant: 38).isActive = true
        knob.heightAnchor.constraint(equalToConstant: 38).isActive = true

        fader.translatesAutoresizingMaskIntoConstraints = false
        fader.widthAnchor.constraint(equalToConstant: 56).isActive = true
        fader.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        fader.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .vertical)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true

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

        let stack = NSStackView(views: [numberLabel, panCaption, knob, fader, valueLabel, nameLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        fader.onChange = { [weak self] value in
            guard let self = self else { return }
            self.valueLabel.stringValue = "\(Int((value * 100).rounded()))%"
            self.onSelect?(self.index)
            self.onVolume?(self.index, value)
        }
        knob.onChange = { [weak self] value in
            guard let self = self else { return }
            self.onSelect?(self.index)
            self.onPan?(self.index, value * 2 - 1)
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
    }

    func update(from layer: LayerState) {
        fader.value = layer.volume
        valueLabel.stringValue = "\(Int((layer.volume * 100).rounded()))%"
        knob.value = (layer.pan + 1) / 2
        muteButton.isOn = layer.muted
        soloButton.isOn = layer.soloed
        if layer.sf2Path == nil {
            nameLabel.stringValue = "vazio"
            nameLabel.toolTip = nil
        } else {
            nameLabel.stringValue = layer.presetName
            nameLabel.toolTip = layer.presetName
        }
    }
}
