import Foundation

enum WordBoundaries {
    private static let wordCharacters = CharacterSet.alphanumerics
        .union(.nonBaseCharacters)
        .union(CharacterSet(charactersIn: "_"))

    static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return wordCharacters.contains(scalar)
    }

    static func word(at index: Int, in text: String) -> NSRange? {
        let value = text as NSString
        guard index >= 0, index < value.length,
              isWordCharacter(value.character(at: index)) else { return nil }
        var start = index
        var end = index + 1
        while start > 0 && isWordCharacter(value.character(at: start - 1)) { start -= 1 }
        while end < value.length && isWordCharacter(value.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    static func next(from index: Int, in text: String) -> Int {
        let value = text as NSString
        var position = min(max(index, 0), value.length)
        while position < value.length && !isWordCharacter(value.character(at: position)) { position += 1 }
        while position < value.length && isWordCharacter(value.character(at: position)) { position += 1 }
        return position
    }

    static func previous(from index: Int, in text: String) -> Int {
        let value = text as NSString
        var position = min(max(index, 0), value.length)
        while position > 0 && !isWordCharacter(value.character(at: position - 1)) { position -= 1 }
        while position > 0 && isWordCharacter(value.character(at: position - 1)) { position -= 1 }
        return position
    }

    static func dragSelection(from anchor: NSRange, to index: Int, in text: String) -> NSRange {
        let length = (text as NSString).length
        let position = min(max(index, 0), length)
        if position >= NSMaxRange(anchor) {
            let target = word(at: position, in: text)
                ?? word(at: previous(from: position, in: text), in: text)
            return NSRange(location: anchor.location,
                           length: max(NSMaxRange(anchor), target.map(NSMaxRange) ?? NSMaxRange(anchor)) - anchor.location)
        }
        if position < anchor.location {
            let target = word(at: position, in: text)
                ?? word(at: next(from: position, in: text) - 1, in: text)
            let start = min(anchor.location, target?.location ?? anchor.location)
            return NSRange(location: start, length: NSMaxRange(anchor) - start)
        }
        return anchor
    }
}
