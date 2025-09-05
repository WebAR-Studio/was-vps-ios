import Foundation
import simd

struct PlyPoint {
    let position: simd_float3
    let color: simd_float3
}

class PlyParser {
    
    enum PlyError: Error {
        case invalidFormat
        case unsupportedFormat
        case missingVertexData
        case parsingError(String)
    }
    
    static func parsePlyData(_ data: Data) throws -> [PlyPoint] {
        print("Starting PLY file parsing, size: \(data.count) bytes")
        
        // Show first characters for debugging
        if data.count > 0 {
            let firstChars = data.prefix(20).map { String(format: "%c", $0) }.joined()
            print("First 20 characters: '\(firstChars)'")
            
            let firstBytes = data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("First 20 bytes: \(firstBytes)")
        }
        
        // First read header as text
        let headerData = data.prefix(4096) // First 4KB for header
        
        // Try different encodings for header
        let headerString: String
        if let asciiString = String(data: headerData, encoding: .ascii) {
            headerString = asciiString
        } else if let utf8String = String(data: headerData, encoding: .utf8) {
            headerString = utf8String
        } else if let isoLatin1String = String(data: headerData, encoding: .isoLatin1) {
            headerString = isoLatin1String
        } else {
            // If decoding failed, show first bytes for debugging
            let firstBytes = data.prefix(100).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("Failed to decode header. First 100 bytes: \(firstBytes)")
            throw PlyError.parsingError("Failed to decode PLY file header")
        }
        
        let headerLines = headerString.components(separatedBy: .newlines)
        var currentLine = 0
        
        print("PLY file header:")
        print(headerString)
        print("--- End of header ---")
        
        // Parse header
        guard headerLines.count > 0, headerLines[currentLine].trimmingCharacters(in: .whitespaces) == "ply" else {
            print("File does not start with 'ply'")
            print("First line: '\(headerLines.first ?? "empty")'")
            throw PlyError.invalidFormat
        }
        currentLine += 1
        
        var format = ""
        var vertexCount = 0
        var hasColor = false
        var colorFormat = "float" // Default is float
        var headerEndIndex = 0
        
        // Read header
        print("Starting header parsing...")
        while currentLine < headerLines.count {
            let line = headerLines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Skip comments
            if line.hasPrefix("comment") {
                print("Comment: \(line)")
                currentLine += 1
                continue
            }
            
            if line.hasPrefix("format") {
                let parts = line.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    format = parts[1]
                    print("Format: \(format)")
                }
            } else if line.hasPrefix("element vertex") {
                let parts = line.components(separatedBy: .whitespaces)
                if parts.count >= 3, let count = Int(parts[2]) {
                    vertexCount = count
                    print("Vertex count: \(vertexCount)")
                }
            } else if line.hasPrefix("element face") {
                // Skip face info - not used
                print("Found faces in PLY file - skipping")
            } else if line.hasPrefix("property") {
                print("Property: \(line)")
                if line.contains("red") || line.contains("green") || line.contains("blue") {
                    hasColor = true
                    // Determine color format
                    let parts = line.components(separatedBy: .whitespaces)
                    if parts.count >= 2 {
                        colorFormat = parts[1] // float, uchar, etc.
                        print("Color format: \(colorFormat)")
                    }
                }
            } else if line == "end_header" {
                print("Header finished")
                // Find end of header position in source data
                if let endHeaderRange = headerString.range(of: "end_header") {
                    headerEndIndex = headerString.distance(from: headerString.startIndex, to: endHeaderRange.upperBound)
                    // Add newline
                    headerEndIndex += 1
                }
                currentLine += 1
                break
            } else if !line.isEmpty {
                print("Unknown header line: \(line)")
            }
            
            currentLine += 1
        }
        
        guard format == "ascii" || format == "binary_little_endian" || format == "binary_big_endian" else {
            throw PlyError.unsupportedFormat
        }
        
        guard vertexCount > 0 else {
            throw PlyError.missingVertexData
        }
        
        print("Parsing PLY file: \(vertexCount) vertices, color: \(hasColor ? "yes (\(colorFormat))" : "no"), format: \(format)")
        
        if format == "ascii" {
            return try parseAsciiFormat(data: data, headerEndIndex: headerEndIndex, vertexCount: vertexCount, hasColor: hasColor, colorFormat: colorFormat)
        } else {
            return try parseBinaryFormat(data: data, headerEndIndex: headerEndIndex, vertexCount: vertexCount, hasColor: hasColor, colorFormat: colorFormat, isLittleEndian: format == "binary_little_endian")
        }
    }
    
    private static func parseAsciiFormat(data: Data, headerEndIndex: Int, vertexCount: Int, hasColor: Bool, colorFormat: String) throws -> [PlyPoint] {
        let pointsData = data.subdata(in: headerEndIndex..<data.count)
        let pointsString = String(data: pointsData, encoding: .utf8) ?? ""
        
        let lines = pointsString.components(separatedBy: .newlines)
        var currentLine = 0
        
        var points: [PlyPoint] = []
        points.reserveCapacity(vertexCount)
        
        for i in 0..<vertexCount {
            guard currentLine < lines.count else {
                throw PlyError.parsingError("Unexpected end of file at line \(currentLine)")
            }
            
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            guard !line.isEmpty else {
                currentLine += 1
                continue
            }
            
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            guard components.count >= 3 else {
                print("Error at line \(currentLine): not enough components (\(components.count))")
                print("Line: '\(line)'")
                throw PlyError.parsingError("Not enough components in line \(currentLine): '\(line)'")
            }
            
            guard let x = Float(components[0]),
                  let y = Float(components[1]),
                  let z = Float(components[2]) else {
                print("Error at line \(currentLine): invalid coordinate format")
                print("Line: '\(line)'")
                print("Components: \(components)")
                throw PlyError.parsingError("Invalid coordinate format in line \(currentLine): '\(line)'")
            }
            
            let position = simd_float3(x, y, z)
            var color = simd_float3(1.0, 1.0, 1.0) // White color by default
            
            // If color data exists
            if hasColor && components.count >= 6 {
                if colorFormat == "uchar" {
                    // For uchar (0-255) convert to float (0.0-1.0)
                    if let r = UInt8(components[3]),
                       let g = UInt8(components[4]),
                       let b = UInt8(components[5]) {
                        color = simd_float3(
                            Float(r) / 255.0,
                            Float(g) / 255.0,
                            Float(b) / 255.0
                        )
                    } else {
                        print("Warning: invalid color format at line \(currentLine)")
                    }
                } else {
                    // For float use values as is
                    if let r = Float(components[3]),
                       let g = Float(components[4]),
                       let b = Float(components[5]) {
                        color = simd_float3(r, g, b)
                    } else {
                        print("Warning: invalid color format at line \(currentLine)")
                    }
                }
            }
            
            points.append(PlyPoint(position: position, color: color))
            currentLine += 1
            
            // Show progress every 10000 points
            if i % 10000 == 0 {
                print("Processed \(i) of \(vertexCount) points")
            }
        }
        
        print("Successfully parsed \(points.count) points")
        
        // Check if there is remaining data (faces)
        if currentLine < lines.count {
            let remainingLines = lines.count - currentLine
            print("Skipping \(remainingLines) lines with face data")
        }
        
        return points
    }
    
    private static func parseBinaryFormat(data: Data, headerEndIndex: Int, vertexCount: Int, hasColor: Bool, colorFormat: String, isLittleEndian: Bool) throws -> [PlyPoint] {
        let pointsData = data.subdata(in: headerEndIndex..<data.count)
        
        print("Data size after header: \(pointsData.count) bytes")
        
        // Calculate expected size of a single vertex
        let vertexSize = 12 + (hasColor ? (colorFormat == "uchar" ? 3 : 12) : 0) // 12 bytes for position + color
        let expectedSize = vertexCount * vertexSize
        print("Expected data size: \(expectedSize) bytes (\(vertexCount) vertices × \(vertexSize) bytes)")
        
        if pointsData.count < expectedSize {
            print("Warning: data size is smaller than expected")
        }
        
        var points: [PlyPoint] = []
        points.reserveCapacity(vertexCount)
        
        var currentOffset = 0
        
        for i in 0..<vertexCount {
            guard currentOffset + 12 <= pointsData.count else {
                throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
            }
            
            // Read position (3 floats of 4 bytes each)
            let xData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
            let x = xData.withUnsafeBytes { $0.load(as: Float.self) }
            currentOffset += 4
            
            guard currentOffset + 8 <= pointsData.count else {
                throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
            }
            
            let yData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
            let y = yData.withUnsafeBytes { $0.load(as: Float.self) }
            currentOffset += 4
            
            guard currentOffset + 4 <= pointsData.count else {
                throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
            }
            
            let zData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
            let z = zData.withUnsafeBytes { $0.load(as: Float.self) }
            currentOffset += 4
            
            let position = simd_float3(x, y, z)
            var color = simd_float3(1.0, 1.0, 1.0) // White color by default
            
            if hasColor {
                guard currentOffset + 3 <= pointsData.count else {
                    throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
                }
                
                if colorFormat == "uchar" {
                    // For uchar read as UInt8
                    let r = UInt8(pointsData[currentOffset])
                    currentOffset += 1
                    
                    guard currentOffset + 2 <= pointsData.count else {
                        throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
                    }
                    
                    let g = UInt8(pointsData[currentOffset])
                    currentOffset += 1
                    
                    guard currentOffset + 1 <= pointsData.count else {
                        throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
                    }
                    
                    let b = UInt8(pointsData[currentOffset])
                    currentOffset += 1
                    
                    color = simd_float3(
                        Float(r) / 255.0,
                        Float(g) / 255.0,
                        Float(b) / 255.0
                    )
                } else {
                    // For float read as Float
                    guard currentOffset + 12 <= pointsData.count else {
                        throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
                    }
                    
                    let rData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
                    let r = rData.withUnsafeBytes { $0.load(as: Float.self) }
                    currentOffset += 4
                    
                    guard currentOffset + 8 <= pointsData.count else {
                        throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
                    }
                    
                    let gData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
                    let g = gData.withUnsafeBytes { $0.load(as: Float.self) }
                    currentOffset += 4
                    
                    guard currentOffset + 4 <= pointsData.count else {
                        throw PlyError.parsingError("Unexpected end of file at offset \(currentOffset)")
                    }
                    
                    let bData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
                    let b = bData.withUnsafeBytes { $0.load(as: Float.self) }
                    currentOffset += 4
                    
                    color = simd_float3(r, g, b)
                }
            }
            
            points.append(PlyPoint(position: position, color: color))
            
            // Show progress every 10000 points
            if i % 10000 == 0 {
                print("Processed \(i) of \(vertexCount) points")
            }
        }
        
        print("Successfully parsed \(points.count) points")
        
        return points
    }
} 