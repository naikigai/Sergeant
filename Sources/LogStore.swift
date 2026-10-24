import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let text: String
}

/// Stores one plain-text file per day in ~/Documents/ActivityLog/YYYY-MM-DD.txt,
/// each line formatted as "HH:mm<TAB>what I did".
final class LogStore: ObservableObject {
    static let shared = LogStore()

    let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/ActivityLog", isDirectory: true)

    @Published var day = Date() { didSet { reload() } }
    @Published private(set) var entries: [LogEntry] = []

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    var isShowingToday: Bool { Calendar.current.isDateInToday(day) }

    func fileURL(for date: Date) -> URL {
        folder.appendingPathComponent(Self.dayFormat.string(from: date) + ".txt")
    }

    func add(_ text: String, at date: Date = Date()) {
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        let line = "\(Self.timeFormat.string(from: date))\t\(clean)\n"
        let url = fileURL(for: date)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }

        if Calendar.current.isDate(day, inSameDayAs: date) { reload() }
    }

    func shiftDay(by days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: day) { day = d }
    }

    func reload() {
        entries = entries(for: day)
    }

    /// The last `count` entries logged today, oldest first.
    func recentEntries(_ count: Int) -> [LogEntry] {
        Array(entries(for: Date()).suffix(count))
    }

    private func entries(for date: Date) -> [LogEntry] {
        let text = (try? String(contentsOf: fileURL(for: date), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            return parts.count == 2
                ? LogEntry(time: String(parts[0]), text: String(parts[1]))
                : LogEntry(time: "", text: String(line))
        }
    }

    var plainText: String {
        entries.map { "\($0.time)  \($0.text)" }.joined(separator: "\n")
    }
}
