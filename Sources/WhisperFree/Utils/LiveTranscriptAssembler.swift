import Foundation

enum LiveTranscriptAssembler {
    struct Pair: Equatable {
        let original: String
        let translated: String
    }

    struct Turn: Equatable {
        let id: UUID
        let pair: Pair
    }

    static func mergeText(previous: String, incoming: String) -> String? {
        mergeText(previous: previous, incoming: incoming, minimumOverlapWordCount: 3)
    }

    static func appendStreamingChunk(previous: String, incoming: String) -> String {
        let previous = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !previous.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return previous }
        return mergeText(previous: previous, incoming: incoming, minimumOverlapWordCount: 1)
            ?? "\(previous) \(incoming)"
    }

    private static func mergeText(previous: String, incoming: String, minimumOverlapWordCount: Int) -> String? {
        let previous = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !previous.isEmpty, !incoming.isEmpty else { return nil }
        if previous == incoming { return previous }

        let previousWords = normalizedWords(previous)
        let incomingWords = normalizedWords(incoming)
        guard !previousWords.isEmpty, !incomingWords.isEmpty else { return nil }

        let previousNormalized = previousWords.joined(separator: " ")
        let incomingNormalized = incomingWords.joined(separator: " ")
        if previousNormalized == incomingNormalized { return previous.count >= incoming.count ? previous : incoming }
        if incomingWords.starts(with: previousWords) { return incoming }
        if previousWords.starts(with: incomingWords) { return previous }
        let overlap = longestWordOverlap(left: previousWords, right: incomingWords)
        if overlap >= minimumOverlapWordCount {
            return appendRemainder(previous: previous, incoming: incoming, dropping: overlap)
        }
        return nil
    }

    static func merge(previous: Pair, incoming: Pair) -> Pair? {
        guard let original = mergeText(previous: previous.original, incoming: incoming.original) else {
            return nil
        }

        let previousOriginalWords = normalizedWords(previous.original)
        let incomingOriginalWords = normalizedWords(incoming.original)
        if incomingOriginalWords.count > previousOriginalWords.count,
           incomingOriginalWords.starts(with: previousOriginalWords) {
            return incoming
        }

        guard let translated = mergeText(previous: previous.translated, incoming: incoming.translated) else {
            return nil
        }
        return Pair(original: original, translated: translated)
    }

    static func merge(previous: Turn, incoming: Turn) -> Turn? {
        guard previous.id == incoming.id,
              let pair = merge(previous: previous.pair, incoming: incoming.pair) else {
            return nil
        }
        return Turn(id: incoming.id, pair: pair)
    }

    static func appendLosslessly(previous: String, incoming: String) -> String {
        let previous = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !previous.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return previous }
        return mergeText(previous: previous, incoming: incoming) ?? "\(previous) \(incoming)"
    }

    private static func appendRemainder(previous: String, incoming: String, dropping count: Int) -> String? {
        let incomingWords = speechTokens(incoming).map(\.original)
        let remainder = incomingWords.dropFirst(count).joined(separator: " ")
        guard !remainder.isEmpty else { return previous }
        return "\(previous) \(remainder)"
    }

    private static func longestWordOverlap(left: [String], right: [String]) -> Int {
        for count in stride(from: min(left.count, right.count), through: 1, by: -1) {
            if Array(left.suffix(count)) == Array(right.prefix(count)) { return count }
        }
        return 0
    }

    private static func normalizedWords(_ text: String) -> [String] {
        speechTokens(text).map(\.normalized)
    }

    private static func speechTokens(_ text: String) -> [(original: String, normalized: String)] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { rawToken in
                let original = String(rawToken)
                let normalized = original.lowercased().filter { $0.isLetter || $0.isNumber }
                return normalized.isEmpty ? nil : (original, normalized)
            }
    }
}

enum LiveTranscriptPresentation {
    static func shouldShowDraft(lastCommittedOriginal: String?, currentOriginal: String) -> Bool {
        let current = currentOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        return lastCommittedOriginal?.trimmingCharacters(in: .whitespacesAndNewlines) != current
    }
}

struct CoalescingRequestGate<Value: Equatable> {
    private struct Entry: Equatable {
        let key: AnyHashable
        let value: Value
    }

    private var activeEntry: Entry?
    private var pendingEntries: [Entry] = []

    var active: Value? { activeEntry?.value }
    var pending: Value? { pendingEntries.first?.value }

    mutating func submit(_ value: Value, coalescingKey: AnyHashable = 0) -> Value? {
        let entry = Entry(key: coalescingKey, value: value)
        guard activeEntry == nil else {
            if activeEntry != entry {
                if let pendingIndex = pendingEntries.firstIndex(where: { $0.key == coalescingKey }) {
                    pendingEntries[pendingIndex] = entry
                } else {
                    pendingEntries.append(entry)
                }
            }
            return nil
        }

        activeEntry = entry
        return value
    }

    mutating func complete() -> Value? {
        activeEntry = nil
        guard !pendingEntries.isEmpty else { return nil }
        let next = pendingEntries.removeFirst()
        activeEntry = next
        return next.value
    }

    mutating func cancel() {
        activeEntry = nil
        pendingEntries.removeAll(keepingCapacity: true)
    }
}

struct LiveSilenceBoundaryGuard {
    private(set) var isRecognitionActive = false

    mutating func beginRecognition() {
        isRecognitionActive = true
    }

    mutating func endRecognition() {
        isRecognitionActive = false
    }

    func shouldRotateTurnOnSilence() -> Bool {
        !isRecognitionActive
    }
}

struct LiveAudioChunkAssembler {
    let overlapByteCount: Int
    private var trailingContext = Data()

    init(overlapByteCount: Int) {
        self.overlapByteCount = max(0, overlapByteCount)
    }

    mutating func makeChunk(from freshAudio: Data) -> Data {
        let chunk = trailingContext + freshAudio
        trailingContext = Data(chunk.suffix(max(0, overlapByteCount)))
        return chunk
    }

    mutating func reset() {
        trailingContext.removeAll(keepingCapacity: true)
    }
}

struct BoundedAudioBuffer {
    let maxByteCount: Int
    private(set) var data = Data()

    var count: Int { data.count }

    init(maxByteCount: Int) {
        self.maxByteCount = max(0, maxByteCount)
    }

    @discardableResult
    mutating func append(_ freshAudio: Data) -> Int {
        data.append(freshAudio)
        let droppedByteCount = max(0, data.count - maxByteCount)
        if droppedByteCount > 0 {
            data = Data(data.suffix(maxByteCount))
        }
        return droppedByteCount
    }

    mutating func consumeAll() -> Data {
        let consumed = data
        data.removeAll(keepingCapacity: true)
        return consumed
    }

    mutating func reset() {
        data.removeAll(keepingCapacity: true)
    }
}
