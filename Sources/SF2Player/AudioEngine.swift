import AVFoundation
import AudioToolbox
import CoreAudio

enum AudioEngineError: LocalizedError {
    case presetNotLoaded

    var errorDescription: String? {
        switch self {
        case .presetNotLoaded:
            return "O motor de áudio não conseguiu carregar este timbre do SoundFont."
        }
    }
}

/// Uma camada (canal): sampler → reverb → mixer (volume/pan).
final class SamplerLayer {
    let sampler = AVAudioUnitSampler()
    let reverb = AVAudioUnitReverb()
    let mixer = AVAudioMixerNode()

    // Roteamento (lido pela thread do MIDI; protegido por routeLock do motor)
    var low: UInt8 = 0
    var high: UInt8 = 127
    var channel: Int = 0          // 0 = Omni
    var transpose: Int = 0
    var hasSound = false
    var active = Set<UInt8>()     // notas (já transpostas) soando

    // Mixagem (somente thread principal)
    var volume: Float = 0.8
    var muted = false
    var soloed = false

    func accepts(channel incoming: Int, note: UInt8) -> Bool {
        guard hasSound, note >= low, note <= high else { return false }
        return incoming == 0 || channel == 0 || channel == incoming
    }
}

/// Motor de áudio com várias camadas independentes (estilo mixer multitimbral).
final class MultiSamplerEngine {

    private let engine = AVAudioEngine()
    private var layers: [SamplerLayer] = []
    private let routeLock = NSLock()
    private let engineLock = NSLock()
    private var configObserver: NSObjectProtocol?
    private var bufferConfigured = false

    init(layerCount: Int) {
        for _ in 0..<layerCount {
            let layer = SamplerLayer()
            engine.attach(layer.sampler)
            engine.attach(layer.reverb)
            engine.attach(layer.mixer)
            engine.connect(layer.sampler, to: layer.reverb, format: nil)
            engine.connect(layer.reverb, to: layer.mixer, format: nil)
            engine.connect(layer.mixer, to: engine.mainMixerNode, format: nil)
            layer.reverb.loadFactoryPreset(.largeHall)
            layer.reverb.wetDryMix = 0
            layer.reverb.bypass = true
            layer.mixer.outputVolume = layer.volume
            layers.append(layer)
        }
        engine.mainMixerNode.outputVolume = 0.8

        // Reinicia o motor se o dispositivo de saída mudar (ex.: plugar fones).
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            try? self?.start()
        }
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Ciclo de vida

    func start() throws {
        engineLock.lock()
        defer { engineLock.unlock() }

        if !bufferConfigured {
            bufferConfigured = true
            MultiSamplerEngine.requestLowLatencyBuffer(frames: 256)
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func stop() {
        panic()
        engine.stop()
    }

    /// Pede ao dispositivo de saída padrão um buffer pequeno (≈ 5,8 ms a 44,1 kHz).
    private static func requestLowLatencyBuffer(frames: UInt32) {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)

        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &defaultDeviceAddress, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return }

        var bufferFrames = frames
        var bufferAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster)
        _ = AudioObjectSetPropertyData(deviceID, &bufferAddress, 0, nil,
                                       UInt32(MemoryLayout<UInt32>.size), &bufferFrames)
    }

    // MARK: - SoundFont por camada

    func loadInstrument(layer index: Int, url: URL, bank: Int, program: Int) throws {
        guard layers.indices.contains(index) else { return }
        engineLock.lock()
        defer { engineLock.unlock() }

        let sampler = layers[index].sampler
        let programNumber = UInt8(clamping: program)
        var attempts: [(msb: UInt8, lsb: UInt8)] = []
        if bank >= 128 {
            attempts = [(0x78, 0)]
        } else {
            let lsb = UInt8(clamping: bank)
            attempts = [(0x79, lsb), (0x00, lsb)]
        }

        var lastError: Error?
        var loaded = false
        for attempt in attempts {
            do {
                try sampler.loadSoundBankInstrument(at: url,
                                                    program: programNumber,
                                                    bankMSB: attempt.msb,
                                                    bankLSB: attempt.lsb)
                loaded = true
                break
            } catch {
                lastError = error
            }
        }
        if !loaded {
            throw lastError ?? AudioEngineError.presetNotLoaded
        }

        routeLock.lock()
        layers[index].hasSound = true
        routeLock.unlock()
    }

    func clearSound(layer index: Int) {
        guard layers.indices.contains(index) else { return }
        routeLock.lock()
        let layer = layers[index]
        layer.hasSound = false
        let notes = Array(layer.active)
        layer.active.removeAll()
        routeLock.unlock()
        for note in notes { layer.sampler.stopNote(note, onChannel: 0) }
    }

    // MARK: - Parâmetros (chamar da thread principal)

    func configure(layer index: Int, low: Int, high: Int, channel: Int, transpose: Int) {
        guard layers.indices.contains(index) else { return }
        routeLock.lock()
        let layer = layers[index]
        layer.low = UInt8(clamping: low)
        layer.high = UInt8(clamping: high)
        layer.channel = max(0, min(16, channel))
        layer.transpose = transpose
        routeLock.unlock()
    }

    func setVolume(_ value: Float, layer index: Int) {
        guard layers.indices.contains(index) else { return }
        layers[index].volume = max(0, min(1, value))
        applyMix()
    }

    func setPan(_ value: Float, layer index: Int) {
        guard layers.indices.contains(index) else { return }
        layers[index].mixer.pan = max(-1, min(1, value))
    }

    func setMute(_ muted: Bool, layer index: Int) {
        guard layers.indices.contains(index) else { return }
        layers[index].muted = muted
        applyMix()
    }

    func setSolo(_ soloed: Bool, layer index: Int) {
        guard layers.indices.contains(index) else { return }
        layers[index].soloed = soloed
        applyMix()
    }

    func setReverb(_ amount: Float, layer index: Int) {
        guard layers.indices.contains(index) else { return }
        let clamped = max(0, min(1, amount))
        layers[index].reverb.wetDryMix = clamped * 100
        layers[index].reverb.bypass = clamped < 0.001
    }

    func setMasterVolume(_ value: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, value))
    }

    /// Ganho extra de 0 a +9 dB aplicado em todas as camadas.
    func setMasterGain(_ decibels: Float) {
        let db = max(0, min(9, decibels))
                for layer in layers {
            if #available(macOS 12.0, *) {
                layer.sampler.overallGain = db
            } else {
                layer.sampler.masterGain = db
            }
        }
    }

    private func applyMix() {
        let anySolo = layers.contains { $0.soloed }
        for layer in layers {
            let silent = layer.muted || (anySolo && !layer.soloed)
            layer.mixer.outputVolume = silent ? 0 : layer.volume
        }
    }

    // MARK: - Notas (podem ser chamadas de qualquer thread, inclusive a do CoreMIDI)
    // channel = 0 → teclado virtual (ignora o filtro de canal MIDI das camadas).

    func noteOn(channel: Int, note: UInt8, velocity: UInt8) {
        guard note < 128 else { return }
        let vel = max(1, min(127, velocity))
        var started: [(SamplerLayer, UInt8)] = []

        routeLock.lock()
        for layer in layers where layer.accepts(channel: channel, note: note) {
            let shifted = Int(note) + layer.transpose
            if shifted >= 0 && shifted <= 127 {
                let transposed = UInt8(shifted)
                layer.active.insert(transposed)
                started.append((layer, transposed))
            }
        }
        routeLock.unlock()

        for (layer, transposed) in started {
            layer.sampler.startNote(transposed, withVelocity: vel, onChannel: 0)
        }
    }

    func noteOff(channel: Int, note: UInt8) {
        guard note < 128 else { return }
        var stopped: [(SamplerLayer, UInt8)] = []

        routeLock.lock()
        for layer in layers {
            let shifted = Int(note) + layer.transpose
            guard shifted >= 0, shifted <= 127 else { continue }
            let transposed = UInt8(shifted)
            if layer.active.contains(transposed) {
                layer.active.remove(transposed)
                stopped.append((layer, transposed))
            }
        }
        routeLock.unlock()

        for (layer, transposed) in stopped {
            layer.sampler.stopNote(transposed, onChannel: 0)
        }
    }

    private func targets(channel: Int) -> [SamplerLayer] {
        routeLock.lock()
        defer { routeLock.unlock() }
        return layers.filter { $0.hasSound && (channel == 0 || $0.channel == 0 || $0.channel == channel) }
    }

    func controlChange(channel: Int, controller: UInt8, value: UInt8) {
        for layer in targets(channel: channel) {
            layer.sampler.sendController(controller, withValue: value, onChannel: 0)
        }
    }

    func pitchBend(channel: Int, value: UInt16) {
        for layer in targets(channel: channel) {
            layer.sampler.sendPitchBend(value, onChannel: 0)
        }
    }

    /// Panic: All Notes Off + All Sound Off + solta pedal em todas as camadas.
    func panic() {
        var pending: [(SamplerLayer, [UInt8])] = []
        routeLock.lock()
        for layer in layers {
            pending.append((layer, Array(layer.active)))
            layer.active.removeAll()
        }
        routeLock.unlock()

        for (layer, notes) in pending {
            for note in notes {
                layer.sampler.stopNote(note, onChannel: 0)
            }
            for channel in 0..<16 {
                let ch = UInt8(channel)
                layer.sampler.sendController(64, withValue: 0, onChannel: ch)    // sustain off
                layer.sampler.sendController(123, withValue: 0, onChannel: ch)   // All Notes Off
                layer.sampler.sendController(120, withValue: 0, onChannel: ch)   // All Sound Off
            }
            layer.sampler.sendPitchBend(8192, onChannel: 0)
        }
    }
}
