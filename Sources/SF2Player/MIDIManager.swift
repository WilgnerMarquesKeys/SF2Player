import CoreMIDI
import Foundation

/// Recebe mensagens de teclados/controladores MIDI USB via CoreMIDI.
/// Os callbacks on* são chamados na thread do CoreMIDI.
final class MIDIManager {

    // Todos os callbacks recebem o canal MIDI (1–16) como primeiro argumento.
    var onNoteOn: ((Int, UInt8, UInt8) -> Void)?
    var onNoteOff: ((Int, UInt8) -> Void)?
    var onControlChange: ((Int, UInt8, UInt8) -> Void)?
    var onPitchBend: ((Int, UInt16) -> Void)?
    var onDevicesChanged: (([String]) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connected = Set<MIDIEndpointRef>()

    // MARK: - Ciclo de vida

    func start() {
        let clientStatus = MIDIClientCreateWithBlock("SF2Player" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.refreshSources() }
            }
        }
        guard clientStatus == noErr else { return }

        let portStatus = MIDIInputPortCreateWithBlock(client, "Entrada SF2Player" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.process(packetList)
        }
        guard portStatus == noErr else { return }

        refreshSources()
    }

    func stop() {
        for endpoint in connected {
            MIDIPortDisconnectSource(inputPort, endpoint)
        }
        connected.removeAll()
        if inputPort != 0 { MIDIPortDispose(inputPort); inputPort = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }

    // MARK: - Dispositivos (hot-plug)

    private func refreshSources() {
        var current = Set<MIDIEndpointRef>()
        var names = [String]()

        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let source = MIDIGetSource(index)
            if source == 0 { continue }
            current.insert(source)
            names.append(displayName(of: source))
        }

        for removed in connected.subtracting(current) {
            MIDIPortDisconnectSource(inputPort, removed)
        }
        for added in current.subtracting(connected) {
            MIDIPortConnectSource(inputPort, added, nil)
        }
        connected = current
        onDevicesChanged?(names)
    }

    private func displayName(of object: MIDIObjectRef) -> String {
        var property: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &property)
        if status == noErr, let value = property {
            return value.takeRetainedValue() as String
        }
        return "Dispositivo MIDI"
    }

    // MARK: - Leitura dos pacotes

    private func process(_ list: UnsafePointer<MIDIPacketList>) {
        let packetCount = Int(list.pointee.numPackets)
        // Layout do CoreMIDI (pack 4): lista = UInt32 numPackets, depois os pacotes;
        // pacote = UInt64 timeStamp (0), UInt16 length (8), bytes de dados (10...).
        var packet = UnsafeRawPointer(list).advanced(by: 4).assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<packetCount {
            let length = Int(packet.pointee.length)
            let dataStart = UnsafeRawPointer(packet).advanced(by: 10).assumingMemoryBound(to: UInt8.self)
            let bytes = Array(UnsafeBufferPointer(start: dataStart, count: length))
            parse(bytes)
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
    }

    private func parse(_ bytes: [UInt8]) {
        var i = 0
        let n = bytes.count

        while i < n {
            let status = bytes[i]

            if status < 0x80 { i += 1; continue }   // byte de dados solto

            if status >= 0xF0 {                      // mensagens de sistema
                switch status {
                case 0xF0:
                    i += 1
                    while i < n && bytes[i] != 0xF7 { i += 1 }
                    i += 1
                case 0xF1, 0xF3:
                    i += 2
                case 0xF2:
                    i += 3
                default:
                    i += 1                           // clock, active sensing etc.
                }
                continue
            }

            let kind = status & 0xF0
            let channel = Int(status & 0x0F) + 1
            let dataLength = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
            guard i + dataLength < n else { break }

            let d1 = bytes[i + 1]
            let d2: UInt8 = (dataLength == 2) ? bytes[i + 2] : 0
            i += 1 + dataLength

            switch kind {
            case 0x90:
                if d2 > 0 { onNoteOn?(channel, d1, d2) } else { onNoteOff?(channel, d1) }
            case 0x80:
                onNoteOff?(channel, d1)
            case 0xB0:
                onControlChange?(channel, d1, d2)
            case 0xE0:
                onPitchBend?(channel, UInt16(d1) | (UInt16(d2) << 7))
            default:
                break
            }
        }
    }
}
