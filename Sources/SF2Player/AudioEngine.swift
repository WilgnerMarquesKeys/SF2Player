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

/// Motor de áudio: AVAudioEngine + AVAudioUnitSampler (carrega .sf2 nativamente).
final class SamplerEngine {

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private let lock = NSLock()
    private let notesLock = NSLock()
    private var activeNotes = Set<UInt8>()
    private var configObserver: NSObjectProtocol?
    private var bufferConfigured = false

    /// Volume master (0.0 – 1.0).
    var masterVolume: Float {
        get { return engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
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
        lock.lock()
        defer { lock.unlock() }

        if !bufferConfigured {
            bufferConfigured = true
            SamplerEngine.requestLowLatencyBuffer(frames: 256)
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
    /// Se o sistema recusar (ex.: sandbox/driver), simplesmente segue com o padrão.
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

    // MARK: - SoundFont

    /// Carrega um preset (banco/programa) de um .sf2 no sampler.
    /// Banco 128 = percussão (MSB 0x78); demais = melódico (MSB 0x79, LSB = banco).
    func loadPreset(from url: URL, bank: Int, program: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        let programNumber = UInt8(clamping: program)
        var attempts: [(msb: UInt8, lsb: UInt8)] = []
        if bank >= 128 {
            attempts = [(0x78, 0)]
        } else {
            let lsb = UInt8(clamping: bank)
            attempts = [(0x79, lsb), (0x00, lsb)]   // 2ª tentativa: mapeamento GM alternativo
        }

        var lastError: Error?
        for attempt in attempts {
            do {
                try sampler.loadSoundBankInstrument(at: url,
                                                    program: programNumber,
                                                    bankMSB: attempt.msb,
                                                    bankLSB: attempt.lsb)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? AudioEngineError.presetNotLoaded
    }

    // MARK: - Notas (podem ser chamadas de qualquer thread, inclusive a do CoreMIDI)

    func noteOn(_ note: UInt8, velocity: UInt8) {
        guard note < 128 else { return }
        let vel = max(1, min(127, velocity))
        notesLock.lock()
        activeNotes.insert(note)
        notesLock.unlock()
        sampler.startNote(note, withVelocity: vel, onChannel: 0)
    }

    func noteOff(_ note: UInt8) {
        guard note < 128 else { return }
        notesLock.lock()
        activeNotes.remove(note)
        notesLock.unlock()
        sampler.stopNote(note, onChannel: 0)
    }

    func controlChange(_ controller: UInt8, value: UInt8) {
        sampler.sendController(controller, withValue: value, onChannel: 0)
    }

    func pitchBend(_ value: UInt16) {
        sampler.sendPitchBend(value, onChannel: 0)
    }

    /// Panic: All Notes Off + All Sound Off + solta pedal em todos os canais.
    func panic() {
        notesLock.lock()
        let notes = activeNotes
        activeNotes.removeAll()
        notesLock.unlock()

        for note in notes {
            sampler.stopNote(note, onChannel: 0)
        }
        for channel in 0..<16 {
            let ch = UInt8(channel)
            sampler.sendController(64, withValue: 0, onChannel: ch)    // sustain off
            sampler.sendController(123, withValue: 0, onChannel: ch)   // All Notes Off
            sampler.sendController(120, withValue: 0, onChannel: ch)   // All Sound Off
        }
        sampler.sendPitchBend(8192, onChannel: 0)
    }
}
