import Foundation

/// Estado de uma camada (um "canal" do mixer).
struct LayerState: Codable {
    var sf2Path: String? = nil
    var bank: Int = 0
    var program: Int = 0
    var presetName: String = ""
    var volume: Double = 0.8      // 0...1
    var pan: Double = 0           // -1...1
    var muted: Bool = false
    var soloed: Bool = false
    var lowNote: Int = 0
    var highNote: Int = 127
    var channel: Int = 0          // 0 = Omni, 1...16
    var transpose: Int = 0        // semitons
    var reverb: Double = 0        // 0...1
}

/// Uma "performance" completa: todas as camadas + master.
struct PerformanceState: Codable {
    var layers: [LayerState]
    var masterVolume: Double = 0.8
    var masterGainDB: Double = 0   // 0...9 dB

    static func empty(layerCount: Int) -> PerformanceState {
        return PerformanceState(layers: Array(repeating: LayerState(), count: layerCount))
    }
}

/// Guarda performances (memórias 1–4 e a última sessão) no UserDefaults.
enum PerformanceStore {
    static func save(_ state: PerformanceState, key: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load(key: String) -> PerformanceState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PerformanceState.self, from: data)
    }
}
