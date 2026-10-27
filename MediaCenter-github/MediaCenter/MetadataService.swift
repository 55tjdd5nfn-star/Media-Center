import Foundation

enum MetadataService {
    private static let userAgent = "MediaCenter/1.0 (personal media app)"

    static func fetchSong(title: String, creator: String, album: String = "") async -> FetchedMetadata {
        var result = FetchedMetadata()

        let mb = await searchMusicBrainz(title: title, creator: creator, album: album)
        if let mb = mb {
            result.title = mb.title
            result.creator = mb.creator
            result.album = mb.album
            result.releaseDate = mb.releaseDate
            result.source = "MusicBrainz"
            if let art = await coverArt(releaseID: mb.releaseID) {
                result.artworkURL = art
            }
        }

        let it = await searchiTunesSong(title: title, creator: creator, album: album)
        if let it = it {
            if result.title.isEmpty { result.title = it.title }
            if result.creator.isEmpty { result.creator = it.creator }
            if result.album.isEmpty { result.album = it.album }
            if result.genre.isEmpty { result.genre = it.genre }
            if result.releaseDate.isEmpty { result.releaseDate = it.releaseDate }
            if result.artworkURL == nil { result.artworkURL = it.artworkURL }
            if result.source.isEmpty { result.source = "iTunes" }
        }

        let lyrics = await searchLyrics(title: result.title.isEmpty ? title : result.title,
                                        creator: result.creator.isEmpty ? creator : result.creator)
        result.lyrics = lyrics.plain
        result.syncedLyrics = lyrics.synced
        return result
    }

    static func fetchSong(for item: MediaItem) async -> FetchedMetadata {
        var title = item.title
        var creator = item.creator
        if title.isEmpty || creator.isEmpty {
            let parsed = parseFilename(item.url)
            if title.isEmpty { title = parsed.title }
            if creator.isEmpty { creator = parsed.creator }
        }
        if title.isEmpty { title = item.url.deletingPathExtension().lastPathComponent }
        return await fetchSong(title: title, creator: creator, album: item.album)
    }

    static func parseFilename(_ url: URL) -> (title: String, creator: String) {
        let base = url.deletingPathExtension().lastPathComponent
        for sep in [" - ", " – ", " — "] {
            let parts = base.components(separatedBy: sep)
            if parts.count >= 2 {
                let creator = parts[0].trimmingCharacters(in: .whitespaces)
                let title = parts[1...].joined(separator: sep).trimmingCharacters(in: .whitespaces)
                if !creator.isEmpty && !title.isEmpty { return (title, creator) }
            }
        }
        return ("", "")
    }

    private static func matchScore(title: String, creator: String, album: String,
                                   knownTitle: String, knownCreator: String, knownAlbum: String) -> Int {
        var score = 0
        let t = title.lowercased().trimmingCharacters(in: .whitespaces)
        let kt = knownTitle.lowercased().trimmingCharacters(in: .whitespaces)
        if !kt.isEmpty {
            if t == kt { score += 2 }
            else if t.contains(kt) || kt.contains(t) { score += 1 }
        }
        let c = creator.lowercased().trimmingCharacters(in: .whitespaces)
        let kc = knownCreator.lowercased().trimmingCharacters(in: .whitespaces)
        if !kc.isEmpty {
            if c == kc { score += 3 }
            else if c.contains(kc) || kc.contains(c) { score += 2 }
        }
        let a = album.lowercased().trimmingCharacters(in: .whitespaces)
        let ka = knownAlbum.lowercased().trimmingCharacters(in: .whitespaces)
        if !ka.isEmpty {
            if a == ka { score += 2 }
            else if a.contains(ka) || ka.contains(a) { score += 1 }
        }
        return score
    }

    private struct MBRecording: Decodable {
        let title: String
        struct ArtistCredit: Decodable {
            struct Artist: Decodable { let name: String }
            let artist: Artist
        }
        let artistCredit: [ArtistCredit]
        struct Release: Decodable {
            let id: String
            let title: String
            let date: String?
        }
        let releases: [Release]?
        enum CodingKeys: String, CodingKey {
            case title, releases
            case artistCredit = "artist-credit"
        }
    }
    private struct MBSearch: Decodable { let recordings: [MBRecording] }

    private struct MBResult {
        let title: String
        let creator: String
        let album: String
        let releaseDate: String
        let releaseID: String
    }

    private static func searchMusicBrainz(title: String, creator: String, album: String = "") async -> MBResult? {
        var parts = ["recording:" + title]
        if !creator.isEmpty { parts.append("artist:" + creator) }
        let query = parts.joined(separator: " AND ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://musicbrainz.org/ws/2/recording/?query=\(encoded)&fmt=json&limit=5") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let search = try? JSONDecoder().decode(MBSearch.self, from: data),
              !search.recordings.isEmpty else { return nil }

        let best = search.recordings.max { a, b in
            let aRel = a.releases?.first
            let bRel = b.releases?.first
            let aScore = matchScore(title: a.title,
                                    creator: a.artistCredit.first?.artist.name ?? "",
                                    album: aRel?.title ?? "",
                                    knownTitle: title, knownCreator: creator, knownAlbum: album)
            let bScore = matchScore(title: b.title,
                                    creator: b.artistCredit.first?.artist.name ?? "",
                                    album: bRel?.title ?? "",
                                    knownTitle: title, knownCreator: creator, knownAlbum: album)
            return aScore < bScore
        }
        guard let rec = best else { return nil }
        let release = rec.releases?.first
        return MBResult(
            title: rec.title,
            creator: rec.artistCredit.first?.artist.name ?? "",
            album: release?.title ?? "",
            releaseDate: release?.date ?? "",
            releaseID: release?.id ?? ""
        )
    }

    private static func coverArt(releaseID: String) async -> URL? {
        guard !releaseID.isEmpty else { return nil }

        let url = URL(string: "https://coverartarchive.org/release/\(releaseID)/front-250")!
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...399).contains(http.statusCode) else { return nil }
        return url
    }

    private struct iTunesSong: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let primaryGenreName: String?
        let releaseDate: String?
        let artworkUrl100: String?
    }
    private struct iTunesSearch: Decodable { let results: [iTunesSong] }

    private struct iTunesResult {
        let title: String
        let creator: String
        let album: String
        let genre: String
        let releaseDate: String
        let artworkURL: URL?
    }

    private static func searchiTunesSong(title: String, creator: String, album: String = "") async -> iTunesResult? {
        let term = ([title, creator].filter { !$0.isEmpty }).joined(separator: " ")
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=5") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let search = try? JSONDecoder().decode(iTunesSearch.self, from: data),
              !search.results.isEmpty else { return nil }

        guard let song = search.results.max(by: { a, b in
            matchScore(title: a.trackName ?? "", creator: a.artistName ?? "", album: a.collectionName ?? "",
                       knownTitle: title, knownCreator: creator, knownAlbum: album)
            < matchScore(title: b.trackName ?? "", creator: b.artistName ?? "", album: b.collectionName ?? "",
                         knownTitle: title, knownCreator: creator, knownAlbum: album)
        }) else { return nil }

        var artURL: URL?
        if let raw = song.artworkUrl100 {
            artURL = URL(string: raw.replacingOccurrences(of: "100x100bb.jpg", with: "600x600bb.jpg"))
        }
        return iTunesResult(
            title: song.trackName ?? "",
            creator: song.artistName ?? "",
            album: song.collectionName ?? "",
            genre: song.primaryGenreName ?? "",
            releaseDate: String((song.releaseDate ?? "").prefix(10)),
            artworkURL: artURL
        )
    }

    private struct LRCLIBResult: Decodable {
        let trackName: String?
        let artistName: String?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static func searchLyrics(title: String, creator: String) async -> (plain: String, synced: String) {
        guard !title.isEmpty else { return ("", "") }
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !creator.isEmpty { items.append(URLQueryItem(name: "artist_name", value: creator)) }
        components.queryItems = items
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let results = try? JSONDecoder().decode([LRCLIBResult].self, from: data),
              !results.isEmpty else { return ("", "") }

        let best = results.first { !($0.syncedLyrics ?? "").isEmpty }
            ?? results.first { !($0.plainLyrics ?? "").isEmpty }
            ?? results.first!
        return (best.plainLyrics ?? "", best.syncedLyrics ?? "")
    }

    static func downloadArtwork(_ url: URL) async -> Data? {
        let (data, response) = (try? await URLSession.shared.data(from: url)) ?? (nil, nil)
        guard let data = data, let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode), !data.isEmpty else { return nil }
        return data
    }
}
