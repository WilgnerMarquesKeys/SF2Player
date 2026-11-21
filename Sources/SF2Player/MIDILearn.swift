import Foundation

/// Tudo que pode ser controlado por um controlador MIDI.
enum MapTarget: Hashable {
    case volume(Int)
    case pan(Int)
    case reverb(Int)
    case mute(Int)
    case solo(Int)
    case masterVolume
    case masterGain

    var key: String {
        switch self {
        case .volume(let i): return "vol.\(i)"
        case .pan(let i): return "pan.\(i)"
        case .reverb(let i): return "rev.\(i)"
        case .mute(let i): return "mute.\(i)"
        case .solo(let i): return "solo.\(i)"
        case .masterVolume: return "master.vol"
        case .masterGain: return "master.gain"
        }
    }

    init?(key: String) {
        if key == "master.vol" { self = .masterVolume; return }
        if key == "master.gain" { self = .masterGain; return }
        let parts = key.split(separator: ".")
        guard parts.count == 2, let i = Int(parts[1]) else { return nil }
        switch String(parts[0]) {
        case "vol": self = .volume(i)
        case "pan": self = .pan(i)
        case "rev": self = .reverb(i)
        case "mute": self = .mute(i)
        case "solo": self = .solo(i)
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .volume(let i): return "Volume da camada \(i + 1)"
        case .pan(let i): return "Pan da camada \(i + 1)"
        case .reverb(let i): return "Reverb da camada \(i + 1)"
        case .mute(let i): return "Mute da camada \(i + 1)"
        case .solo(let i): return "Solo da camada \(i + 1)"
        case .masterVolume: return "Volume master"
        case .masterGain: return "Ganho master"
        }
    }
}

/// Qual controle (CC) de qual canal MIDI está ligado a um alvo.
struct MIDIBinding: Codable, Equatable {
    var channel: Int      // 1...16
    var controller: Int   // 0...127
}

/// Guarda os mapeamentos e lembra deles entre aberturas do app.
/// Pode ser consultado da thread do CoreMIDI (protegido por lock).
final class MIDIMapStore {
    private let lock = NSLock()
    private var bindings: [String: MIDIBinding] = [:]
    private var learning = false
    private let defaultsKey = "midi.bindings"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: MIDIBinding].self, from: data) {
            bindings = decoded
        }
    }

    var isLearning: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return learning
        }
        set {
            lock.lock()
            learning = newValue
            lock.unlock()
        }
    }

    func target(channel: Int, controller: Int) -> MapTarget? {
        lock.lock()
        defer { lock.unlock() }
        for (key, binding) in bindings where binding.channel == channel && binding.controller == controller {
            return MapTarget(key: key)
        }
        return nil
    }

    func binding(for target: MapTarget) -> MIDIBinding? {
        lock.lock()
        defer { lock.unlock() }
        return bindings[target.key]
    }

    func assign(_ target: MapTarget, channel: Int, controller: Int) {
        lock.lock()
        defer { lock.unlock() }
        // um mesmo controle físico só pode ter um destino
        let existing = bindings
        for (key, binding) in existing where binding.channel == channel && binding.controller == controller {
            bindings.removeValue(forKey: key)
        }
        bindings[target.key] = MIDIBinding(channel: channel, controller: controller)
        saveLocked()
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        bindings.removeAll()
        saveLocked()
    }

    private func saveLocked() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
