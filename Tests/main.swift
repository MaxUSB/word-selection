import Foundation

let domain = "example.com/path"
precondition(WordBoundaries.word(at: 2, in: domain) == NSRange(location: 0, length: 7))
precondition(WordBoundaries.word(at: 8, in: domain) == NSRange(location: 8, length: 3))
precondition(WordBoundaries.word(at: 7, in: domain) == nil)
precondition(WordBoundaries.next(from: 0, in: domain) == 7)
precondition(WordBoundaries.next(from: 7, in: domain) == 11)
precondition(WordBoundaries.previous(from: 11, in: domain) == 8)
precondition(WordBoundaries.previous(from: 8, in: domain) == 0)
let com = NSRange(location: 8, length: 3)
precondition(WordBoundaries.dragSelection(from: com, to: 9, in: domain) == com)
precondition(WordBoundaries.dragSelection(from: com, to: 7, in: domain) == com)
precondition(WordBoundaries.dragSelection(from: com, to: 2, in: domain) == NSRange(location: 0, length: 11))
let example = NSRange(location: 0, length: 7)
precondition(WordBoundaries.dragSelection(from: example, to: 7, in: domain) == example)
precondition(WordBoundaries.dragSelection(from: example, to: 9, in: domain) == NSRange(location: 0, length: 11))
precondition(WordBoundaries.dragSelection(from: example, to: 11, in: domain) == NSRange(location: 0, length: 11))
precondition(WordBoundaries.dragSelection(from: example, to: 13, in: domain) == NSRange(location: 0, length: 16))

let unicode = "  привет, мир_2!"
precondition(WordBoundaries.word(at: 3, in: unicode) == NSRange(location: 2, length: 6))
precondition(WordBoundaries.next(from: 8, in: unicode) == 15)
precondition(WordBoundaries.previous(from: 15, in: unicode) == 10)
precondition(WordBoundaries.previous(from: 2, in: unicode) == 0)
precondition(WordBoundaries.next(from: 16, in: unicode) == 16)
print("Word boundaries: OK")
