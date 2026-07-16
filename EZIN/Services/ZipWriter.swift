import Foundation

/// Minimal, correct ZIP archive writer (stored / no compression).
/// Produces fully valid archives: real CRC-32 checksums, accurate sizes and
/// offsets in both the local headers and the central directory, so files open
/// in Files, macOS Finder, Windows Explorer and every standard unzip tool.
enum ZipWriter {

    struct Entry {
        let name: String
        let data: Data
    }

    /// Build a ZIP archive from in-memory entries. Returns nil when there is nothing to pack.
    static func makeZip(entries: [Entry]) -> Data? {
        let valid = entries.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !valid.isEmpty else { return nil }

        var zip = Data()
        var central: [(name: Data, crc: UInt32, size: UInt32, offset: UInt32)] = []

        for entry in valid {
            let cleanName = entry.name.replacingOccurrences(of: "\\", with: "/")
            guard let nameData = cleanName.data(using: .utf8) else { continue }
            let crc = crc32(entry.data)
            let offset = UInt32(zip.count)

            // Local file header
            zip.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
            zip.appendLE(UInt16(20))                          // version needed (2.0)
            zip.appendLE(UInt16(0))                           // flags
            zip.appendLE(UInt16(0))                           // method: stored
            zip.appendLE(UInt16(0))                           // mod time
            zip.appendLE(UInt16(0x21))                        // mod date (1980-01-01)
            zip.appendLE(crc)
            zip.appendLE(UInt32(entry.data.count))            // compressed size
            zip.appendLE(UInt32(entry.data.count))            // uncompressed size
            zip.appendLE(UInt16(nameData.count))
            zip.appendLE(UInt16(0))                           // extra length
            zip.append(nameData)
            zip.append(entry.data)

            central.append((nameData, crc, UInt32(entry.data.count), offset))
        }

        // Central directory
        let centralStart = UInt32(zip.count)
        for item in central {
            zip.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
            zip.appendLE(UInt16(20))           // version made by
            zip.appendLE(UInt16(20))           // version needed
            zip.appendLE(UInt16(0))            // flags
            zip.appendLE(UInt16(0))            // method
            zip.appendLE(UInt16(0))            // time
            zip.appendLE(UInt16(0x21))         // date
            zip.appendLE(item.crc)
            zip.appendLE(item.size)            // compressed
            zip.appendLE(item.size)            // uncompressed
            zip.appendLE(UInt16(item.name.count))
            zip.appendLE(UInt16(0))            // extra
            zip.appendLE(UInt16(0))            // comment
            zip.appendLE(UInt16(0))            // disk number
            zip.appendLE(UInt16(0))            // internal attrs
            zip.appendLE(UInt32(0))            // external attrs
            zip.appendLE(item.offset)
            zip.append(item.name)
        }
        let centralSize = UInt32(zip.count) - centralStart

        // End of central directory
        zip.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(central.count))
        zip.appendLE(UInt16(central.count))
        zip.appendLE(centralSize)
        zip.appendLE(centralStart)
        zip.appendLE(UInt16(0))

        return zip
    }

    /// CRC-32 (ISO 3309 / ITU-T V.42) as required by the ZIP format.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    /// Append a little-endian integer's raw bytes.
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
