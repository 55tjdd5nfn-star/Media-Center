import Foundation

enum MediaKind: String, Codable {
    case song
    case movie
    case video
}

struct MediaItem: Identifiable, Codable {
    var id: UUID
    let url: URL
    let kind: MediaKind
    var title: String
    var creator: String
    var album: String
    var genre: String
    var releaseDate: String
    var trackNumber: Int
    var duration: Double
    var lyrics: String
    var syncedLyrics: String
    var artworkPath: String
    var lastPosition: Double
    var dateAdded: Date
    var lastPlayedAt: Date? = nil
    var playable: Bool
    var source: String

    var fileID: UInt64 = 0

    var releaseYear: String {
        releaseDate.prefix(4).description
    }

    var displayCreator: String {
        creator.isEmpty ? "Unknown Artist" : creator
    }

    var displayTitle: String {
        title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
    }
}

struct CaptionCue: Codable {
    let start: Double
    let end: Double
    let text: String
}

struct PlaylistEntry: Codable, Hashable {
    let path: String
    let fileID: UInt64
}

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var entries: [PlaylistEntry]
}

struct FetchedMetadata {
    var title = ""
    var creator = ""
    var album = ""
    var genre = ""
    var releaseDate = ""
    var trackNumber = 0
    var lyrics = ""
    var syncedLyrics = ""
    var artworkURL: URL?
    var source = ""
}

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}

enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }
            guard let close = line.firstIndex(of: "]") else { continue }
            let stamp = String(line[line.index(after: line.startIndex)..<close])
            let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let parts = stamp.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]) else { continue }

            let secParts = parts[1].split(separator: ".")
            guard let seconds = Double(secParts[0]) else { continue }
            var time = minutes * 60 + seconds
            if secParts.count > 1, let frac = Double("0." + secParts[1]) {
                time += frac
            }
            lines.append(LyricLine(time: time, text: text))
        }
        return lines.sorted { $0.time < $1.time }
    }
}
