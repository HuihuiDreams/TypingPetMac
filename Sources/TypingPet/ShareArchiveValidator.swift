import Foundation
import zlib

/// Validate ZIP directories and decode only bounded regular files.
/// Only regular files and directories, stored/deflated data, and bounded sizes are accepted.
enum ShareArchiveValidator {
    static func validate(_ data: Data, extractingTo directory: URL? = nil) throws {
        func fail() throws -> Never { throw LocalShareError.invalidPackage }
        func u16(_ offset: Int) throws -> Int {
            guard offset >= 0, offset + 2 <= data.count else { try fail() }
            return Int(data[offset]) | Int(data[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> Int {
            try u16(offset) | u16(offset + 2) << 16
        }
        guard data.count >= 22, data.count <= 50 * 1024 * 1024 else { try fail() }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try u32(offset) == 0x06054b50, offset + 22 + (try u16(offset + 20)) == data.count {
                end = offset; break
            }
        }
        guard let end, try u16(end + 4) == 0, try u16(end + 6) == 0 else { try fail() }
        let count = try u16(end + 10)
        guard count > 0, count <= 200, try u16(end + 8) == count else { try fail() }
        let start = try u32(end + 16)
        guard start + (try u32(end + 12)) == end else { try fail() }
        var offset = start
        var expanded = 0
        var names = Set<String>()
        var ranges: [Range<Int>] = []
        for _ in 0..<count {
            guard try u32(offset) == 0x02014b50 else { try fail() }
            let flags = try u16(offset + 8), method = try u16(offset + 10)
            let compressed = try u32(offset + 20), size = try u32(offset + 24)
            let length = try u16(offset + 28), extra = try u16(offset + 30), comment = try u16(offset + 32)
            let local = try u32(offset + 42), mode = try u32(offset + 38) >> 16
            let next = offset + 46 + length + extra + comment
            guard next <= end, length > 0, flags & 1 == 0, [0, 8].contains(method),
                  try u16(offset + 34) == 0, compressed < 0xffffffff, size <= 50 * 1024 * 1024,
                  [0, 0o100000, 0o040000].contains(mode & 0o170000),
                  let name = String(data: data.subdata(in: offset + 46..<offset + 46 + length), encoding: .utf8),
                  !name.contains("\\"), !name.contains("\0"), !name.hasPrefix("/"),
                  names.insert(name.lowercased()).inserted else { try fail() }
            let trimmed = name.hasSuffix("/") ? String(name.dropLast()) : name
            let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
            guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") }),
                  name == "manifest.json" || name == "images/" || (components.count == 2 && components[0] == "images"),
                  !name.hasSuffix("/") || size == 0 else { try fail() }
            expanded += size
            guard expanded <= 200 * 1024 * 1024,
                  local >= 0, local + 30 <= start, try u32(local) == 0x04034b50,
                  try u16(local + 6) == flags, try u16(local + 8) == method else { try fail() }
            let localLength = try u16(local + 26), localExtra = try u16(local + 28)
            let payload = local + 30 + localLength + localExtra
            guard localLength == length, payload + compressed <= start,
                  data.subdata(in: local + 30..<local + 30 + localLength) == data.subdata(in: offset + 46..<offset + 46 + length),
                  !ranges.contains(where: { $0.overlaps(local..<payload + compressed) }) else { try fail() }
            if flags & 8 == 0 {
                guard try u32(local + 18) == compressed, try u32(local + 22) == size else { try fail() }
            }
            try verifyPayload(data, offset: payload, compressed: compressed, size: size,
                              method: method, checksum: u32(offset + 16),
                              destination: name.hasSuffix("/") ? nil : directory?.appendingPathComponent(name))
            ranges.append(local..<payload + compressed)
            offset = next
        }
        guard offset == end, names.contains("manifest.json") else { try fail() }
    }

    private static func verifyPayload(_ data: Data, offset: Int, compressed: Int, size: Int,
                                      method: Int, checksum: Int, destination file: URL?) throws {
        // Verify real decoded length and CRC before an extractor can write any files.
        // A forged ZIP directory cannot conceal a much larger deflate stream.
        var output = [UInt8](repeating: 0, count: max(1, size + 1))
        try output.withUnsafeMutableBufferPointer { destination in
            try data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                let input = source.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: offset)
                if method == 0 {
                    guard compressed == size else { throw LocalShareError.invalidPackage }
                    let actual = crc32(0, input, uInt(size))
                    guard actual == uLong(checksum) else { throw LocalShareError.invalidPackage }
                    if let file {
                        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                                attributes: [.posixPermissions: 0o700])
                        try Data(bytes: input, count: size).write(to: file, options: .atomic)
                    }
                } else {
                    var stream = z_stream()
                    guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                        throw LocalShareError.invalidPackage
                    }
                    defer { inflateEnd(&stream) }
                    stream.next_in = UnsafeMutablePointer(mutating: input)
                    stream.avail_in = uInt(compressed)
                    stream.next_out = destination.baseAddress!
                    stream.avail_out = uInt(destination.count)
                    guard inflate(&stream, Z_FINISH) == Z_STREAM_END,
                          stream.total_out == uLong(size), stream.total_in == uLong(compressed),
                          crc32(0, destination.baseAddress!, uInt(size)) == uLong(checksum) else {
                        throw LocalShareError.invalidPackage
                    }
                    if let file {
                        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                                attributes: [.posixPermissions: 0o700])
                        try Data(bytesNoCopy: destination.baseAddress!, count: size, deallocator: .none).write(to: file, options: .atomic)
                    }
                }
            }
        }
    }

}
