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
        print("Начинаем парсинг PLY файла, размер: \(data.count) байт")
        
        // Показываем первые символы для отладки
        if data.count > 0 {
            let firstChars = data.prefix(20).map { String(format: "%c", $0) }.joined()
            print("Первые 20 символов: '\(firstChars)'")
            
            let firstBytes = data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("Первые 20 байт: \(firstBytes)")
        }
        
        // Сначала читаем заголовок как текст
        let headerData = data.prefix(4096) // Первые 4KB для заголовка
        
        // Пробуем разные кодировки для заголовка
        let headerString: String
        if let asciiString = String(data: headerData, encoding: .ascii) {
            headerString = asciiString
        } else if let utf8String = String(data: headerData, encoding: .utf8) {
            headerString = utf8String
        } else if let isoLatin1String = String(data: headerData, encoding: .isoLatin1) {
            headerString = isoLatin1String
        } else {
            // Если не удалось декодировать, показываем первые байты для отладки
            let firstBytes = data.prefix(100).map { String(format: "%02X", $0) }.joined(separator: " ")
            print("Не удалось декодировать заголовок. Первые 100 байт: \(firstBytes)")
            throw PlyError.parsingError("Не удалось декодировать заголовок PLY файла")
        }
        
        let headerLines = headerString.components(separatedBy: .newlines)
        var currentLine = 0
        
        print("Заголовок PLY файла:")
        print(headerString)
        print("--- Конец заголовка ---")
        
        // Парсим заголовок
        guard headerLines.count > 0, headerLines[currentLine].trimmingCharacters(in: .whitespaces) == "ply" else {
            print("Файл не начинается с 'ply'")
            print("Первая строка: '\(headerLines.first ?? "пустая")'")
            throw PlyError.invalidFormat
        }
        currentLine += 1
        
        var format = ""
        var vertexCount = 0
        var hasColor = false
        var colorFormat = "float" // По умолчанию float
        var headerEndIndex = 0
        
        // Читаем заголовок
        print("Начинаем парсинг заголовка...")
        while currentLine < headerLines.count {
            let line = headerLines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Пропускаем комментарии
            if line.hasPrefix("comment") {
                print("Комментарий: \(line)")
                currentLine += 1
                continue
            }
            
            if line.hasPrefix("format") {
                let parts = line.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    format = parts[1]
                    print("Формат: \(format)")
                }
            } else if line.hasPrefix("element vertex") {
                let parts = line.components(separatedBy: .whitespaces)
                if parts.count >= 3, let count = Int(parts[2]) {
                    vertexCount = count
                    print("Количество вершин: \(vertexCount)")
                }
            } else if line.hasPrefix("element face") {
                // Пропускаем информацию о гранях - мы их не используем
                print("Найдены грани в PLY файле - пропускаем")
            } else if line.hasPrefix("property") {
                print("Свойство: \(line)")
                if line.contains("red") || line.contains("green") || line.contains("blue") {
                    hasColor = true
                    // Определяем формат цвета
                    let parts = line.components(separatedBy: .whitespaces)
                    if parts.count >= 2 {
                        colorFormat = parts[1] // float, uchar, etc.
                        print("Формат цвета: \(colorFormat)")
                    }
                }
            } else if line == "end_header" {
                print("Заголовок завершен")
                // Находим позицию конца заголовка в исходных данных
                if let endHeaderRange = headerString.range(of: "end_header") {
                    headerEndIndex = headerString.distance(from: headerString.startIndex, to: endHeaderRange.upperBound)
                    // Добавляем перевод строки
                    headerEndIndex += 1
                }
                currentLine += 1
                break
            } else if !line.isEmpty {
                print("Неизвестная строка заголовка: \(line)")
            }
            
            currentLine += 1
        }
        
        guard format == "ascii" || format == "binary_little_endian" || format == "binary_big_endian" else {
            throw PlyError.unsupportedFormat
        }
        
        guard vertexCount > 0 else {
            throw PlyError.missingVertexData
        }
        
        print("Парсим PLY файл: \(vertexCount) вершин, цвет: \(hasColor ? "да (\(colorFormat))" : "нет"), формат: \(format)")
        
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
                throw PlyError.parsingError("Неожиданный конец файла на строке \(currentLine)")
            }
            
            let line = lines[currentLine].trimmingCharacters(in: .whitespaces)
            
            // Пропускаем пустые строки
            guard !line.isEmpty else {
                currentLine += 1
                continue
            }
            
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            guard components.count >= 3 else {
                print("Ошибка в строке \(currentLine): недостаточно компонентов (\(components.count))")
                print("Строка: '\(line)'")
                throw PlyError.parsingError("Недостаточно компонентов в строке \(currentLine): '\(line)'")
            }
            
            guard let x = Float(components[0]),
                  let y = Float(components[1]),
                  let z = Float(components[2]) else {
                print("Ошибка в строке \(currentLine): неверный формат координат")
                print("Строка: '\(line)'")
                print("Компоненты: \(components)")
                throw PlyError.parsingError("Неверный формат координат в строке \(currentLine): '\(line)'")
            }
            
            let position = simd_float3(x, y, z)
            var color = simd_float3(1.0, 1.0, 1.0) // Белый цвет по умолчанию
            
            // Если есть цветовые данные
            if hasColor && components.count >= 6 {
                if colorFormat == "uchar" {
                    // Для uchar (0-255) конвертируем в float (0.0-1.0)
                    if let r = UInt8(components[3]),
                       let g = UInt8(components[4]),
                       let b = UInt8(components[5]) {
                        color = simd_float3(
                            Float(r) / 255.0,
                            Float(g) / 255.0,
                            Float(b) / 255.0
                        )
                    } else {
                        print("Предупреждение: неверный формат цвета в строке \(currentLine)")
                    }
                } else {
                    // Для float используем значения как есть
                    if let r = Float(components[3]),
                       let g = Float(components[4]),
                       let b = Float(components[5]) {
                        color = simd_float3(r, g, b)
                    } else {
                        print("Предупреждение: неверный формат цвета в строке \(currentLine)")
                    }
                }
            }
            
            points.append(PlyPoint(position: position, color: color))
            currentLine += 1
            
            // Показываем прогресс каждые 10000 точек
            if i % 10000 == 0 {
                print("Обработано \(i) из \(vertexCount) точек")
            }
        }
        
        print("Успешно распарсено \(points.count) точек")
        
        // Проверяем, есть ли еще данные (грани)
        if currentLine < lines.count {
            let remainingLines = lines.count - currentLine
            print("Пропускаем \(remainingLines) строк с данными граней")
        }
        
        return points
    }
    
    private static func parseBinaryFormat(data: Data, headerEndIndex: Int, vertexCount: Int, hasColor: Bool, colorFormat: String, isLittleEndian: Bool) throws -> [PlyPoint] {
        let pointsData = data.subdata(in: headerEndIndex..<data.count)
        
        print("Размер данных после заголовка: \(pointsData.count) байт")
        
        // Вычисляем ожидаемый размер одной вершины
        let vertexSize = 12 + (hasColor ? (colorFormat == "uchar" ? 3 : 12) : 0) // 12 байт для позиции + цвет
        let expectedSize = vertexCount * vertexSize
        print("Ожидаемый размер данных: \(expectedSize) байт (\(vertexCount) вершин × \(vertexSize) байт)")
        
        if pointsData.count < expectedSize {
            print("Предупреждение: размер данных меньше ожидаемого")
        }
        
        var points: [PlyPoint] = []
        points.reserveCapacity(vertexCount)
        
        var currentOffset = 0
        
        for i in 0..<vertexCount {
            guard currentOffset + 12 <= pointsData.count else {
                throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
            }
            
            // Читаем позицию (3 float по 4 байта каждый)
            let xData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
            let x = xData.withUnsafeBytes { $0.load(as: Float.self) }
            currentOffset += 4
            
            guard currentOffset + 8 <= pointsData.count else {
                throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
            }
            
            let yData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
            let y = yData.withUnsafeBytes { $0.load(as: Float.self) }
            currentOffset += 4
            
            guard currentOffset + 4 <= pointsData.count else {
                throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
            }
            
            let zData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
            let z = zData.withUnsafeBytes { $0.load(as: Float.self) }
            currentOffset += 4
            
            let position = simd_float3(x, y, z)
            var color = simd_float3(1.0, 1.0, 1.0) // Белый цвет по умолчанию
            
            if hasColor {
                guard currentOffset + 3 <= pointsData.count else {
                    throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
                }
                
                if colorFormat == "uchar" {
                    // Для uchar читаем как UInt8
                    let r = UInt8(pointsData[currentOffset])
                    currentOffset += 1
                    
                    guard currentOffset + 2 <= pointsData.count else {
                        throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
                    }
                    
                    let g = UInt8(pointsData[currentOffset])
                    currentOffset += 1
                    
                    guard currentOffset + 1 <= pointsData.count else {
                        throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
                    }
                    
                    let b = UInt8(pointsData[currentOffset])
                    currentOffset += 1
                    
                    color = simd_float3(
                        Float(r) / 255.0,
                        Float(g) / 255.0,
                        Float(b) / 255.0
                    )
                } else {
                    // Для float читаем как Float
                    guard currentOffset + 12 <= pointsData.count else {
                        throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
                    }
                    
                    let rData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
                    let r = rData.withUnsafeBytes { $0.load(as: Float.self) }
                    currentOffset += 4
                    
                    guard currentOffset + 8 <= pointsData.count else {
                        throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
                    }
                    
                    let gData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
                    let g = gData.withUnsafeBytes { $0.load(as: Float.self) }
                    currentOffset += 4
                    
                    guard currentOffset + 4 <= pointsData.count else {
                        throw PlyError.parsingError("Неожиданный конец файла на позиции \(currentOffset)")
                    }
                    
                    let bData = pointsData.subdata(in: currentOffset..<currentOffset + 4)
                    let b = bData.withUnsafeBytes { $0.load(as: Float.self) }
                    currentOffset += 4
                    
                    color = simd_float3(r, g, b)
                }
            }
            
            points.append(PlyPoint(position: position, color: color))
            
            // Показываем прогресс каждые 10000 точек
            if i % 10000 == 0 {
                print("Обработано \(i) из \(vertexCount) точек")
            }
        }
        
        print("Успешно распарсено \(points.count) точек")
        
        return points
    }
} 