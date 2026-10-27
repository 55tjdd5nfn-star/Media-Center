import AVFoundation
import AppKit
import Foundation

final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var songs: [MediaItem] = []
    @Published private(set) var movies: [MediaItem] = []
    @Published private(set) var videos: [MediaItem] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var isScanning = false
    @Published var lastScanError: String?

    private(set) var manualFiles: [URL] = []

    @Published var musicFolder: URL {
        didSet { UserDefaults.standard.set(musicFolder.path, forKey: "mc.musicFolder") }
    }
    @Published var movieFolder: URL {
        didSet { UserDefaults.standard.set(movieFolder.path, forKey: "mc.movieFolder") }
    }

    private let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "flac", "wav", "aiff", "aif", "alac", "mp2", "m4b", "caf"]

    private let playableVideoExtensions: Set<String> = ["mp4", "m4v", "mov", "3gp", "3g2"]

    private let unplayableVideoExtensions: Set<String> = ["mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "ogg", "ogv", "vob", "m2ts", "mts", "divx"]
    private let allVideoExtensions: Set<String>

    private init() {
        allVideoExtensions = playableVideoExtensions.union(unplayableVideoExtensions)
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let defaultMusic = home.appendingPathComponent("Music/Music/Media")
        let defaultMovies = home.appendingPathComponent("Movies")
        if let saved = UserDefaults.standard.string(forKey: "mc.musicFolder") {
            musicFolder = URL(fileURLWithPath: saved)
        } else {
            musicFolder = defaultMusic
        }
        if let saved = UserDefaults.standard.string(forKey: "mc.movieFolder") {
            movieFolder = URL(fileURLWithPath: saved)
        } else {
            movieFolder = defaultMovies
        }
        if let saved = UserDefaults.standard.stringArray(forKey: "mc.manualFiles") {
            manualFiles = saved.map { URL(fileURLWithPath: $0) }
        }
        loadCache()
        loadPlaylists()
    }

    static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MediaCenter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func artworkDirectory() -> URL {
        let dir = supportDirectory().appendingPathComponent("Artwork")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func captionsDirectory() -> URL {
        let dir = supportDirectory().appendingPathComponent("Captions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var cacheURL: URL { Self.supportDirectory().appendingPathComponent("library.json") }
    private var playlistsURL: URL { Self.supportDirectory().appendingPathComponent("playlists.json") }

    private var sessionURL: URL { Self.supportDirectory().appendingPathComponent("session.json") }
    private struct ExitSession: Codable {
        let itemID: UUID
        let position: Double
    }

    static func fileID(of url: URL) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let num = attrs[.systemFileNumber] as? NSNumber else { return 0 }
        return num.uint64Value
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        lastScanError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                let folderSongs = await self.scanFolder(self.musicFolder, kind: .song)
                let folderVideos = await self.scanFolder(self.movieFolder, kind: .movie)

                let manualSongs = await self.scanFiles(self.manualFiles.filter { self.audioExtensions.contains($0.pathExtension.lowercased()) }, kind: .song)
                let manualVideos = await self.scanFiles(self.manualFiles.filter { self.allVideoExtensions.contains($0.pathExtension.lowercased()) }, kind: .movie)
                let allSongs = Self.dedup(folderSongs + manualSongs)
                let allVideos = Self.dedup(folderVideos + manualVideos)
                await MainActor.run {
                    self.merge(found: allSongs, kind: .song)
                    self.merge(found: allVideos.filter { $0.kind == .movie }, kind: .movie)
                    self.merge(found: allVideos.filter { $0.kind == .video }, kind: .video)
                    self.isScanning = false
                    self.applyExitSessionOnce()
                    self.saveCache()
                }
            }
        }
    }

    func addManualFiles(_ urls: [URL], to playlist: Playlist? = nil) {
        var changed = false
        for url in urls where !manualFiles.contains(url) {
            manualFiles.append(url)
            changed = true
        }
        if changed {
            UserDefaults.standard.set(manualFiles.map { $0.path }, forKey: "mc.manualFiles")
            scan()
        }

        if let playlist = playlist {
            addPaths(urls.map { $0.path }, to: playlist)
        }
    }

    func addPaths(_ paths: [String], to playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        var changed = false
        for path in paths {
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard audioExtensions.contains(ext) || allVideoExtensions.contains(ext) else { continue }
            guard !playlists[index].entries.contains(where: { $0.path == path }) else { continue }
            playlists[index].entries.append(PlaylistEntry(path: path, fileID: 0))
            changed = true
        }
        if changed { savePlaylists() }
    }

    private static func dedup(_ items: [MediaItem]) -> [MediaItem] {
        Dictionary(grouping: items, by: { $0.url.path }).compactMap { $0.value.first }
    }

    private func scanFiles(_ urls: [URL], kind: MediaKind) async -> [MediaItem] {
        var items: [MediaItem] = []
        for url in urls {
            if let item = await readItem(url: url, kind: kind) {
                items.append(item)
            }
        }
        return items
    }

    private func scanFolder(_ folder: URL, kind: MediaKind) async -> [MediaItem] {
        var items: [MediaItem] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return items
        }

        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            switch kind {
            case .song:
                guard audioExtensions.contains(ext) else { continue }
            case .movie, .video:
                guard allVideoExtensions.contains(ext) else { continue }
            }
            if let item = await readItem(url: url, kind: kind) {
                items.append(item)
            }
        }
        return items
    }

    private func readItem(url: URL, kind: MediaKind) async -> MediaItem? {
        let asset = AVAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }

        var actualKind = kind
        if kind == .movie {
            actualKind = seconds >= 2400 ? .movie : .video
        }
        var title = ""
        var creator = ""
        var album = ""
        var genre = ""
        var releaseDate = ""
        var trackNumber = 0
        var artworkData: Data?
        if let common = try? await asset.load(.commonMetadata) {
            for item in common {
                guard let key = item.commonKey else { continue }
                let value = try? await item.load(.value)
                switch key {
                case .commonKeyTitle: title = value as? String ?? ""
                case .commonKeyArtist: creator = value as? String ?? ""
                case .commonKeyAlbumName: album = value as? String ?? ""
                case .commonKeyType: genre = value as? String ?? ""
                case .commonKeyCreationDate:
                    if let date = value as? Date {
                        releaseDate = Self.dateFormatter.string(from: date)
                    } else if let string = value as? String {
                        releaseDate = String(string.prefix(10))
                    }
                case .commonKeyArtwork:
                    artworkData = value as? Data
                default: break
                }
            }
        }

        if let itunes = try? await asset.loadMetadata(for: .iTunesMetadata) {
            for item in itunes {
                guard let key = item.identifier else { continue }
                if key == .iTunesMetadataTrackNumber {
                    if let data = try? await item.load(.dataValue), data.count >= 4 {
                        trackNumber = Int(data[3])
                    }
                }
            }
        }
        let playable: Bool
        switch actualKind {
        case .song: playable = true
        case .movie, .video: playable = playableVideoExtensions.contains(url.pathExtension.lowercased())
        }
        var media = MediaItem(
            id: UUID(), url: url, kind: actualKind,
            title: title, creator: creator, album: album, genre: genre,
            releaseDate: releaseDate, trackNumber: trackNumber,
            duration: seconds, lyrics: "", syncedLyrics: "",
            artworkPath: "", lastPosition: 0, dateAdded: Date(),
            playable: playable, source: "file",
            fileID: Self.fileID(of: url)
        )
        if let data = artworkData, !data.isEmpty {
            media.artworkPath = saveArtwork(data, for: media.id)
        }
        return media
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func saveArtwork(_ data: Data, for id: UUID) -> String {
        Self.saveArtworkFile(data, for: id)
    }

    static func saveArtworkFile(_ data: Data, for id: UUID) -> String {
        let path = Self.artworkDirectory().appendingPathComponent(id.uuidString + ".jpg")

        let toWrite = ImageCache.downscaledJPEGData(data, maxDimension: 600) ?? data
        try? toWrite.write(to: path)
        return path.path
    }

    private func merge(found: [MediaItem], kind: MediaKind) {
        let existing: [MediaItem]
        switch kind {
        case .song: existing = songs
        case .movie: existing = movies
        case .video: existing = videos
        }
        let byPath = Dictionary(uniqueKeysWithValues: existing.map { ($0.url.path, $0) })
        var byFileID: [UInt64: MediaItem] = [:]
        for item in existing where item.fileID != 0 {
            byFileID[item.fileID] = item
        }
        var merged: [MediaItem] = []
        for var item in found {
            let old = byPath[item.url.path]
                ?? (item.fileID != 0 ? byFileID[item.fileID] : nil)
            if let old = old {

                item.id = old.id
                if old.source == "web" {
                    item.title = old.title
                    item.creator = old.creator
                    item.album = old.album
                    item.genre = old.genre
                    item.releaseDate = old.releaseDate
                    item.trackNumber = old.trackNumber
                    item.lyrics = old.lyrics
                    item.syncedLyrics = old.syncedLyrics
                    item.artworkPath = old.artworkPath
                    item.source = old.source
                }
                item.lastPosition = old.lastPosition
                item.dateAdded = old.dateAdded
            }
            merged.append(item)
        }
        merged = Self.dedup(merged)
        switch kind {
        case .song: songs = merged.sorted { $0.displayTitle < $1.displayTitle }
        case .movie: movies = merged.sorted { $0.displayTitle < $1.displayTitle }
        case .video: videos = merged.sorted { $0.displayTitle < $1.displayTitle }
        }
    }

    func saveExitSession() {
        guard let current = PlayerManager.shared.current else {
            try? FileManager.default.removeItem(at: sessionURL)
            return
        }
        let session = ExitSession(itemID: current.id, position: PlayerManager.shared.position)
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: sessionURL, options: .atomic)
        }
    }

    private var didApplySession = false
    private func applyExitSessionOnce() {
        guard !didApplySession else { return }
        didApplySession = true
        applyExitSession()
    }

    private func applyExitSession() {
        for i in songs.indices {
            songs[i].lastPosition = 0
        }
        defer { try? FileManager.default.removeItem(at: sessionURL) }
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(ExitSession.self, from: data) else { return }
        if let i = songs.firstIndex(where: { $0.id == session.itemID }) {
            songs[i].lastPosition = session.position
        } else if let i = movies.firstIndex(where: { $0.id == session.itemID }) {
            movies[i].lastPosition = session.position
        } else if let i = videos.firstIndex(where: { $0.id == session.itemID }) {
            videos[i].lastPosition = session.position
        }
    }

    @discardableResult
    func delete(_ item: MediaItem) -> Bool {
        if PlayerManager.shared.current?.id == item.id {
            PlayerManager.shared.stop()
        }
        PlayerManager.shared.removeFromQueue(item)
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        } catch {
            return false
        }
        removeFromAllPlaylists(item)
        removeFromLibrary(item)
        if let idx = manualFiles.firstIndex(of: item.url) {
            manualFiles.remove(at: idx)
            UserDefaults.standard.set(manualFiles.map { $0.path }, forKey: "mc.manualFiles")
        }
        if !item.artworkPath.isEmpty {
            try? FileManager.default.removeItem(atPath: item.artworkPath)
        }
        return true
    }

    func delete(_ items: [MediaItem]) -> (deleted: Int, failed: Int) {
        var deleted = 0
        var failed = 0
        for item in items {
            if delete(item) { deleted += 1 } else { failed += 1 }
        }
        return (deleted, failed)
    }

    private func removeFromLibrary(_ item: MediaItem) {
        switch item.kind {
        case .song: songs.removeAll { $0.id == item.id }
        case .movie: movies.removeAll { $0.id == item.id }
        case .video: videos.removeAll { $0.id == item.id }
        }
        saveCache()
    }

    func update(_ item: MediaItem) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.update(item) }
            return
        }
        switch item.kind {
        case .song:
            songs.removeAll { $0.id != item.id && $0.url.path == item.url.path }
            if let i = songs.firstIndex(where: { $0.id == item.id }) { songs[i] = item }
        case .movie:
            movies.removeAll { $0.id != item.id && $0.url.path == item.url.path }
            if let i = movies.firstIndex(where: { $0.id == item.id }) { movies[i] = item }
        case .video:
            videos.removeAll { $0.id != item.id && $0.url.path == item.url.path }
            if let i = videos.firstIndex(where: { $0.id == item.id }) { videos[i] = item }
        }

        if PlayerManager.shared.current?.id == item.id {
            PlayerManager.shared.refreshCurrent(item)
        }
        saveCache()
    }

    func isLoadedInPlayer(_ item: MediaItem) -> Bool {
        PlayerManager.shared.current?.id == item.id
    }

    var recentSongs: [MediaItem] {
        Array(songs.filter { $0.lastPlayedAt != nil && !isInPlaylist($0) }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            .prefix(10))
    }

    func markPlayed(_ item: MediaItem) {
        guard item.kind == .song else { return }
        var updated = item
        updated.lastPlayedAt = Date()
        update(updated)
    }

    func saveArtworkData(_ data: Data, for item: MediaItem) -> String {
        saveArtwork(data, for: item.id)
    }

    func applyFetched(_ fetched: FetchedMetadata, to song: MediaItem) async -> MediaItem {
        var updated = song
        var changed = false
        if updated.title.isEmpty, !fetched.title.isEmpty { updated.title = fetched.title; changed = true }
        if updated.creator.isEmpty, !fetched.creator.isEmpty { updated.creator = fetched.creator; changed = true }
        if updated.album.isEmpty, !fetched.album.isEmpty { updated.album = fetched.album; changed = true }
        if updated.genre.isEmpty, !fetched.genre.isEmpty { updated.genre = fetched.genre; changed = true }
        if updated.releaseDate.isEmpty, !fetched.releaseDate.isEmpty { updated.releaseDate = fetched.releaseDate; changed = true }
        if updated.trackNumber == 0, fetched.trackNumber > 0 { updated.trackNumber = fetched.trackNumber; changed = true }
        if updated.lyrics.isEmpty, !fetched.lyrics.isEmpty { updated.lyrics = fetched.lyrics; changed = true }
        if updated.syncedLyrics.isEmpty, !fetched.syncedLyrics.isEmpty { updated.syncedLyrics = fetched.syncedLyrics; changed = true }
        updated.source = "web"

        if updated.artworkPath.isEmpty, let artURL = fetched.artworkURL, let data = await MetadataService.downloadArtwork(artURL) {
            let path = saveArtworkData(data, for: updated)
            if path != updated.artworkPath { updated.artworkPath = path; changed = true }
        }
        update(updated)

        if changed, let written = await writeTagsToFile(updated) {
            updated = written
        }
        return updated
    }

    func writeTagsToFile(_ item: MediaItem) async -> MediaItem? {
        guard item.url.pathExtension.lowercased() == "m4a" else { return nil }
        guard PlayerManager.shared.current?.id != item.id else { return nil }
        let asset = AVAsset(url: item.url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return nil }
        var metadata: [AVMetadataItem] = []
        func add(_ identifier: AVMetadataIdentifier, _ value: String) {
            guard !value.isEmpty else { return }
            let meta = AVMutableMetadataItem()
            meta.identifier = identifier
            meta.value = value as NSString
            meta.extendedLanguageTag = "und"
            metadata.append(meta)
        }
        add(.commonIdentifierTitle, item.title)
        add(.commonIdentifierArtist, item.creator)
        add(.commonIdentifierAlbumName, item.album)

        if !item.releaseDate.isEmpty,
           let date = Self.dateFormatter.date(from: String(item.releaseDate.prefix(10))) {
            let meta = AVMutableMetadataItem()
            meta.identifier = .commonIdentifierCreationDate
            meta.value = date as NSDate
            meta.extendedLanguageTag = "und"
            metadata.append(meta)
        }
        if !item.artworkPath.isEmpty,
           let artData = try? Data(contentsOf: URL(fileURLWithPath: item.artworkPath)), !artData.isEmpty {
            let meta = AVMutableMetadataItem()
            meta.identifier = .commonIdentifierArtwork
            meta.value = artData as NSData
            if artData.starts(with: [0xFF, 0xD8]) {
                meta.dataType = "com.apple.metadata.datatype.JPEG"
            } else if artData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                meta.dataType = "com.apple.metadata.datatype.PNG"
            }
            meta.extendedLanguageTag = "und"
            metadata.append(meta)
        }
        session.metadata = metadata
        session.outputFileType = .m4a
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        session.outputURL = temp
        await session.export()
        guard session.status == .completed else { return nil }
        do {
            let backup = item.url.deletingPathExtension().appendingPathExtension("m4a.bak")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: item.url, to: backup)
            try FileManager.default.moveItem(at: temp, to: item.url)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            return nil
        }

        var updated = item
        updated.fileID = Self.fileID(of: item.url)
        update(updated)
        return updated
    }

    func loadThumbnail(for movie: MediaItem) async -> String {
        if !movie.artworkPath.isEmpty { return movie.artworkPath }
        let path = await Task.detached {
            let asset = AVAsset(url: movie.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)
            let time = CMTime(seconds: max(1, movie.duration * 0.1), preferredTimescale: 600)
            guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { return "" }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .jpeg, properties: [:]) else { return "" }
            return Self.saveArtworkFile(data, for: movie.id)
        }.value
        guard !path.isEmpty else { return "" }
        var updated = movie
        updated.artworkPath = path
        update(updated)
        return path
    }

    var musicSongs: [MediaItem] {
        songs.filter { !isInPlaylist($0) }
    }

    var moviesNotInPlaylist: [MediaItem] {
        movies.filter { !isInPlaylist($0) }
    }

    var videosNotInPlaylist: [MediaItem] {
        videos.filter { !isInPlaylist($0) }
    }

    func playlistContaining(_ item: MediaItem) -> Playlist? {
        playlists.first { playlist in
            playlist.entries.contains { $0.path == item.url.path || ($0.fileID != 0 && $0.fileID == item.fileID) }
        }
    }

    func isInPlaylist(_ item: MediaItem) -> Bool {
        playlistContaining(item) != nil
    }

    func removeFromAllPlaylists(_ item: MediaItem) {
        var changed = false
        for i in playlists.indices {
            let before = playlists[i].entries.count
            playlists[i].entries.removeAll { $0.path == item.url.path || ($0.fileID != 0 && $0.fileID == item.fileID) }
            if playlists[i].entries.count != before { changed = true }
        }
        if changed { savePlaylists() }
    }

    func createPlaylist(name: String) -> Playlist {
        let playlist = Playlist(id: UUID(), name: name, entries: [])
        playlists.append(playlist)
        savePlaylists()
        return playlist
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }

    func addItem(_ item: MediaItem, to playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        guard !playlists[index].entries.contains(where: { $0.path == item.url.path }) else { return }
        playlists[index].entries.append(PlaylistEntry(path: item.url.path, fileID: item.fileID))
        savePlaylists()
    }

    func addItems(withIDs ids: [UUID], to playlist: Playlist) {
        for id in ids {
            if let item = item(withID: id) {
                addItem(item, to: playlist)
            }
        }
    }

    func moveItems(withIDs ids: [UUID], to playlist: Playlist) {
        for id in ids {
            if let item = item(withID: id) {
                removeFromAllPlaylists(item)
            }
        }
        addItems(withIDs: ids, to: playlist)
    }

    func removeItemsFromPlaylists(ids: [UUID]) {
        for id in ids {
            if let item = item(withID: id) {
                removeFromAllPlaylists(item)
            }
        }
    }

    private func item(withID id: UUID) -> MediaItem? {
        songs.first { $0.id == id }
            ?? movies.first { $0.id == id }
            ?? videos.first { $0.id == id }
    }

    func items(for playlist: Playlist) -> [MediaItem] {
        let current = playlists.first(where: { $0.id == playlist.id }) ?? playlist
        return current.entries.compactMap { entry in
            item(withPath: entry.path, fileID: entry.fileID)
        }
    }

    private func item(withPath path: String, fileID: UInt64) -> MediaItem? {
        songs.first { $0.url.path == path }
            ?? movies.first { $0.url.path == path }
            ?? videos.first { $0.url.path == path }
            ?? (fileID != 0 ? songs.first { $0.fileID == fileID }
                ?? movies.first { $0.fileID == fileID }
                ?? videos.first { $0.fileID == fileID } : nil)
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            try? data.write(to: playlistsURL)
        }
    }

    private func loadPlaylists() {
        guard let data = try? Data(contentsOf: playlistsURL),
              let saved = try? JSONDecoder().decode([Playlist].self, from: data) else { return }
        playlists = saved
    }

    private var saveWorkItem: DispatchWorkItem?

    private func saveCache() {
        let snapshot = songs + movies + videos
        let url = cacheURL
        saveWorkItem?.cancel()
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url)
            }
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let items = try? JSONDecoder().decode([MediaItem].self, from: data) else { return }

        songs = Self.dedup(items.filter { $0.kind == .song }).sorted { $0.displayTitle < $1.displayTitle }
        movies = Self.dedup(items.filter { $0.kind == .movie }).sorted { $0.displayTitle < $1.displayTitle }
        videos = Self.dedup(items.filter { $0.kind == .video }).sorted { $0.displayTitle < $1.displayTitle }
    }
}
