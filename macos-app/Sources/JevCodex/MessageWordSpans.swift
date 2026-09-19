import Foundation

/// Mechanical source coordinates only. Jev decides meaning and verbatim protection.
enum MessageWordSpans {
    struct Word {
        let text: String
        let range: NSRange
        let deletionRange: NSRange
    }

    static func index(_ text: String) -> [Word] {
        var words: [Word] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text[cursor].isWhitespace { cursor = text.index(after: cursor); continue }
            let start = cursor
            while cursor < text.endIndex && !text[cursor].isWhitespace { cursor = text.index(after: cursor) }
            let end = cursor
            while cursor < text.endIndex && (text[cursor] == " " || text[cursor] == "\t") { cursor = text.index(after: cursor) }
            words.append(Word(text: String(text[start..<end]), range: NSRange(start..<end, in: text),
                deletionRange: NSRange(start..<cursor, in: text)))
        }
        return words
    }

    static func removing(_ ranges: [NSRange], from text: String) -> String {
        let result = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) { result.deleteCharacters(in: range) }
        return result as String
    }
}
