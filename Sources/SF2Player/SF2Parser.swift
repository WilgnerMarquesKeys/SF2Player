import Foundation

/// Um preset (timbre) dentro de um arquivo SoundFont.
struct SF2Preset {
    let name: String
    let bank: Int      // wBank   (0–127 melódico, 128 = percussão)
    let program: Int   // wPreset (0–127)
}

/// Resultado da leitura de um arquivo .sf2.
struct SF2File {
    let name: String?
    let presets: [SF2Preset]
}

enum SF2Error: LocalizedError {
    case unreadable(String)
    case notSoundFont
    case missingPresetData
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            return "Não foi possível ler o arquivo (\(detail))."
        case .notSoundFont:
            return "O arquivo não parece ser um SoundFont .sf2 válido (cabeçalho RIFF/sfbk ausente)."
        case .missingPresetData:
            return "O arquivo não contém a seção de presets (pdta/phdr) ou está corrompido."
        case .empty:
            return "O SoundFont não contém nenhum preset."
        }
    }
}

/// Leitor binário mínimo (little-endian) com checagem de limites.
private struct ByteReader {
    let data: Data

    var count: Int { return data.count }

    func byte(_ offset: Int) -> Int {
        guard offset >= 0, offset < data.count else { return 0 }
        return Int(data[data.startIndex + offset])
    }

    func u16(_ offset: Int) -> Int {
        let b0 = byte(offset)
        let b1 = byte(offset + 1)
        return b0 | (b1 << 8)
    }

    func u32(_ offset: Int) -> Int {
        let b0 = byte(offset)
        let b1 = byte(offset + 1)
        let b2 = byte(offset + 2)
        let b3 = byte(offset + 3)
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    func fourCC(_ offset: Int) -> String {
        var bytes = [UInt8]()
        for i in 0..<4 { bytes.append(UInt8(byte(offset + i))) }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    /// Lê uma string terminada em NUL (campo de tamanho fixo).
    func string(_ offset: Int, maxLength: Int) -> String {
        var bytes = [UInt8]()
        for i in 0..<maxLength {
            let b = byte(offset + i)
            if b == 0 { break }
            bytes.append(UInt8(b))
        }
        return String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1)
            ?? ""
    }
}

/// Parser de SoundFont 2 em Swift puro.
/// Estrutura: RIFF 'sfbk' → LIST 'INFO' | LIST 'sdta' | LIST 'pdta' (phdr, pbag, pmod, pgen, inst, ...).
/// Só precisamos do 'phdr' (38 bytes por preset); as amostras (sdta) são puladas.
enum SF2Parser {

    private static let phdrRecordSize = 38

    static func parse(url: URL) throws -> SF2File {
        let data: Data
        do {
            // mappedIfSafe evita carregar SoundFonts de centenas de MB na RAM.
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw SF2Error.unreadable(error.localizedDescription)
        }

        let reader = ByteReader(data: data)
        guard reader.count >= 12,
              reader.fourCC(0) == "RIFF",
              reader.fourCC(8) == "sfbk" else {
            throw SF2Error.notSoundFont
        }

        let riffEnd = min(reader.count, 8 + reader.u32(4))
        var offset = 12
        var bankName: String?
        var presets: [SF2Preset]?

        while offset + 8 <= riffEnd {
            let id = reader.fourCC(offset)
            let size = reader.u32(offset + 4)
            let body = offset + 8
            let chunkEnd = min(body + size, reader.count)

            if id == "LIST" {
                let listType = reader.fourCC(body)
                if listType == "INFO" {
                    bankName = readBankName(reader, start: body + 4, end: chunkEnd)
                } else if listType == "pdta" {
                    presets = readPresetHeaders(reader, start: body + 4, end: chunkEnd)
                    break
                }
            }
            offset = body + size + (size & 1)   // chunks são alinhados em 2 bytes
        }

        guard let found = presets else { throw SF2Error.missingPresetData }
        guard !found.isEmpty else { throw SF2Error.empty }

        let sorted = found.sorted { a, b in
            if a.bank != b.bank { return a.bank < b.bank }
            return a.program < b.program
        }
        return SF2File(name: bankName, presets: sorted)
    }

    private static func readBankName(_ reader: ByteReader, start: Int, end: Int) -> String? {
        var offset = start
        while offset + 8 <= end {
            let id = reader.fourCC(offset)
            let size = reader.u32(offset + 4)
            let body = offset + 8
            if id == "INAM" {
                let name = reader.string(body, maxLength: min(size, 256))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
            offset = body + size + (size & 1)
        }
        return nil
    }

    private static func readPresetHeaders(_ reader: ByteReader, start: Int, end: Int) -> [SF2Preset]? {
        var offset = start
        while offset + 8 <= end {
            let id = reader.fourCC(offset)
            let size = reader.u32(offset + 4)
            let body = offset + 8

            if id == "phdr" {
                let recordCount = size / phdrRecordSize
                guard recordCount >= 2 else { return [] }

                var result = [SF2Preset]()
                // O último registro é o terminador "EOP" e deve ser ignorado.
                for index in 0..<(recordCount - 1) {
                    let base = body + index * phdrRecordSize
                    let rawName = reader.string(base, maxLength: 20)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let program = reader.u16(base + 20)   // wPreset
                    let bank = reader.u16(base + 22)      // wBank
                    let name = rawName.isEmpty ? "Preset \(index + 1)" : rawName
                    result.append(SF2Preset(name: name, bank: bank, program: program))
                }
                return result
            }
            offset = body + size + (size & 1)
        }
        return nil
    }
}
