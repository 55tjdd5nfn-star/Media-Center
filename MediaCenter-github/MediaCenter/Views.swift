import AVKit
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum LibraryTab: String, CaseIterable {
    case music = "Music"
    case movies = "Movies"
    case videos = "Videos"
}

struct ContentView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab: LibraryTab = .music
    @State private var searchText = ""
    @State private var selectedSong: MediaItem?
    @State private var selectedMovie: MediaItem?
    @State private var showingMoviePlayer = false
    @State private var choosingMusicFolder = false
    @State private var choosingMovieFolder = false
    @State private var addingFiles = false
    @State private var pendingImportURLs: [URL] = []
    @State private var showingImportDestination = false
    @State private var selectedPlaylist: Playlist?
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var musicDropTargeted = false

    var body: some View {
        ZStack {

            LinearGradient(
                colors: colorScheme == .dark
                    ? [.indigo.opacity(0.55), .pink.opacity(0.45),
                       .purple.opacity(0.50), .teal.opacity(0.40)]
                    : [.indigo.opacity(0.28), .pink.opacity(0.26),
                       .purple.opacity(0.22), .teal.opacity(0.20)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.pink.opacity(colorScheme == .dark ? 0.30 : 0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -260, y: -240)
                .ignoresSafeArea()
            Circle()
                .fill(Color.indigo.opacity(colorScheme == .dark ? 0.30 : 0.18))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 280, y: 260)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    sidebar
                    Divider()
                    VStack(spacing: 0) {
                        if let playlist = selectedPlaylist {
                            PlaylistDetailView(playlist: playlist)
                        } else {
                            switch tab {
                            case .music:
                                MusicListView(searchText: $searchText, selectedSong: $selectedSong)
                            case .movies:
                                VideoGridView(title: "Movies", items: library.moviesNotInPlaylist, searchText: $searchText, selectedMovie: $selectedMovie, showingPlayer: $showingMoviePlayer)
                            case .videos:
                                VideoGridView(title: "Videos", items: library.videosNotInPlaylist, searchText: $searchText, selectedMovie: $selectedMovie, showingPlayer: $showingMoviePlayer)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                NowPlayingBar()
            }
        }
        .searchable(text: $searchText, prompt: "Search your library")
        .fileImporter(isPresented: $choosingMusicFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                library.musicFolder = url
                library.scan()
            }
        }
        .fileImporter(isPresented: $choosingMovieFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                library.movieFolder = url
                library.scan()
            }
        }
        .fileImporter(isPresented: $addingFiles, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, !urls.isEmpty {

                pendingImportURLs = urls
                showingImportDestination = true
            }
        }
        .sheet(isPresented: $showingImportDestination) {
            ImportDestinationView(urls: pendingImportURLs)
        }
        .onAppear { library.scan() }
        .sheet(item: $selectedSong) { song in
            MetadataEditorView(item: song)
        }
        .sheet(isPresented: $showingMoviePlayer) {
            if let movie = selectedMovie {
                MoviePlayerView(movie: movie)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                Text("Media Center")
                    .font(.headline)
            }
            .padding(.bottom, 10)

            ForEach(LibraryTab.allCases, id: \.self) { item in
                Button(action: {
                    tab = item
                    selectedPlaylist = nil
                }) {
                    HStack {
                        Image(systemName: item == .music ? "music.note" : item == .movies ? "film" : "video")
                        Text(item.rawValue)
                            .font(.subheadline)
                            .bold(tab == item)
                        Spacer()
                        Text(item == .music ? "\(library.musicSongs.count)" : item == .movies ? "\(library.moviesNotInPlaylist.count)" : "\(library.videosNotInPlaylist.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)

                    .background(
                        Group {
                            if tab == item {
                                Color.clear.liquidGlass(cornerRadius: 10)
                            } else if item == .music && musicDropTargeted {
                                Color.accentColor.opacity(0.3)
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                .onDrop(of: [mediaIDsPasteboardType], isTargeted: item == .music ? $musicDropTargeted : .constant(false)) { providers in
                    guard item == .music, let provider = providers.first else { return false }
                    provider.loadDataRepresentation(forTypeIdentifier: mediaIDsPasteboardType) { data, _ in
                        guard let data = data, let text = String(data: data, encoding: .utf8) else { return }
                        let ids = text.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
                        Task { @MainActor in
                            LibraryStore.shared.removeItemsFromPlaylists(ids: ids)
                        }
                    }
                    return true
                }
            }

            Text("Playlists")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            ForEach(library.playlists) { playlist in
                PlaylistSidebarRow(
                    playlist: playlist,
                    isSelected: selectedPlaylist?.id == playlist.id,
                    onSelect: { selectedPlaylist = playlist },
                    onDelete: {
                        library.deletePlaylist(playlist)
                        if selectedPlaylist?.id == playlist.id { selectedPlaylist = nil }
                    }
                )
            }
            Button(action: { showingNewPlaylist = true }) {
                Label("New Playlist…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            .alert("New Playlist", isPresented: $showingNewPlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let created = library.createPlaylist(name: name)
                    newPlaylistName = ""
                    selectedPlaylist = created
                }
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
            }

            Spacer()

            Button(action: { library.scan() }) {
                Label(library.isScanning ? "Scanning…" : "Rescan library", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            .disabled(library.isScanning)

            Button(action: { choosingMusicFolder = true }) {
                Label("Choose music folder…", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            Button(action: { choosingMovieFolder = true }) {
                Label("Choose movies folder…", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            Button(action: { addingFiles = true }) {
                Label("Add files…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)

            Divider()
                .padding(.vertical, 4)

            Button(action: {
                library.saveExitSession()
                NSApplication.shared.terminate(nil)
            }) {
                Label("Exit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)

            if let error = library.lastScanError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Text("Music: \(library.musicFolder.path)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text("Movies: \(library.movieFolder.path)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 240)
    }
}

struct ImportDestinationView: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let urls: [URL]
    @State private var newPlaylistName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add \(urls.count) \(urls.count == 1 ? "file" : "files") to…")
                .font(.headline)
            Button(action: { add(to: nil) }) {
                Label("Music Library", systemImage: "music.note")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            ForEach(library.playlists) { playlist in
                Button(action: { add(to: playlist) }) {
                    Label(playlist.name, systemImage: "music.note.list")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .bigGlassButton(cornerRadius: 12)
            }
            Divider()
            HStack {
                TextField("New playlist name", text: $newPlaylistName)
                    .textFieldStyle(.roundedBorder)
                Button("Create & Add") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let created = library.createPlaylist(name: name)
                    add(to: created)
                }
                .buttonStyle(.plain)
                .bigGlassButton(cornerRadius: 12)
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 340)
    }

    private func add(to playlist: Playlist?) {
        library.addManualFiles(urls, to: playlist)
        dismiss()
    }
}

let mediaIDsPasteboardType = "com.mediacenter.media-ids"

struct PlaylistSidebarRow: View {
    @EnvironmentObject var library: LibraryStore
    let playlist: Playlist
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isDropTarget = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "music.note.list")
                Text(playlist.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text("\(library.items(for: playlist).count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Group {
                    if isSelected {
                        Color.clear.liquidGlass(cornerRadius: 10)
                    } else if isDropTarget {
                        Color.accentColor.opacity(0.3)
                    } else {
                        Color.clear
                    }
                }
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete playlist", role: .destructive) { onDelete() }
        }
        .onDrop(of: [mediaIDsPasteboardType], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }

            provider.loadDataRepresentation(forTypeIdentifier: mediaIDsPasteboardType) { [playlist] data, _ in
                guard let data = data, let text = String(data: data, encoding: .utf8) else { return }
                let ids = text.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
                Task { @MainActor in
                    LibraryStore.shared.moveItems(withIDs: ids, to: playlist)
                }
            }
            return true
        }
    }
}

struct MusicListView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerManager
    @Binding var searchText: String
    @Binding var selectedSong: MediaItem?
    @State private var fetchingMissing = false
    @State private var fetchProgress = ""
    @State private var fetchingLyrics = false
    @State private var lyricsProgress = ""
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var pendingAddSong: MediaItem?
    @State private var showingAlbums = false
    @State private var selectedAlbum: String?
    @State private var selectedIDs: Set<MediaItem.ID> = []
    @State private var itemsToDelete: [MediaItem] = []
    @State private var showingDeleteConfirm = false
    @State private var deleteNote = ""

    var filtered: [MediaItem] {
        guard !searchText.isEmpty else { return library.musicSongs }
        let q = searchText.lowercased()
        return library.musicSongs.filter {
            $0.displayTitle.lowercased().contains(q)
            || $0.displayCreator.lowercased().contains(q)
            || $0.album.lowercased().contains(q)
        }
    }

    var albums: [(name: String, songs: [MediaItem])] {
        let grouped = Dictionary(grouping: library.musicSongs, by: { $0.album.isEmpty ? "Unknown Album" : $0.album })
        return grouped.map { (name: $0.key, songs: $0.value) }.sorted { $0.name < $1.name }
    }

    var blankCount: Int {
        library.musicSongs.filter { $0.title.isEmpty || $0.creator.isEmpty }.count
    }

    var lyricsMissingCount: Int {

        library.musicSongs.filter { !$0.title.isEmpty && $0.syncedLyrics.isEmpty }.count
    }

    var body: some View {
        VStack(spacing: 0) {

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Music")
                        .font(.title2)
                        .bold()
                    Text("\(library.musicSongs.count) songs · \(albums.count) albums")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Select All") { selectedIDs = Set(library.musicSongs.map { $0.id }) }
                    .keyboardShortcut("a", modifiers: .command)
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                if blankCount > 0 {
                    Button(fetchingMissing ? "Fetching… \(fetchProgress)" : "Fill in \(blankCount) blank songs") {
                        fetchMissing()
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    .disabled(fetchingMissing)
                }
                if lyricsMissingCount > 0 {
                    Button(fetchingLyrics ? "Finding lyrics… \(lyricsProgress)" : "Find \(lyricsMissingCount) missing lyrics") {
                        fetchMissingLyrics()
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    .disabled(fetchingLyrics)
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text("Tip: drag songs, movies or videos onto a playlist in the sidebar to move them there.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            if !deleteNote.isEmpty {
                Text(deleteNote)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            if !selectedIDs.isEmpty {
                HStack {
                    Text("\(selectedIDs.count) selected")
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    Menu("Move to Playlist") {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.name) {

                                library.moveItems(withIDs: Array(selectedIDs), to: playlist)
                                selectedIDs.removeAll()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    Button("Delete", role: .destructive) {
                        itemsToDelete = library.songs.filter { selectedIDs.contains($0.id) }
                        showingDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    Button("Clear") { selectedIDs.removeAll() }
                        .buttonStyle(.plain)
                        .bigGlassButton(cornerRadius: 10)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            if let albumName = selectedAlbum,
               let album = albums.first(where: { $0.name == albumName }) {
                albumDetailView(album)
            } else {
                Picker("View", selection: $showingAlbums) {
                    Text("Songs").tag(false)
                    Text("Albums").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                if showingAlbums {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                            ForEach(albums, id: \.name) { album in
                                AlbumCard(name: album.name, songs: album.songs)
                                    .onTapGesture { selectedAlbum = album.name }
                                    .onDrag {

                                        let text = album.songs.map { $0.id.uuidString }.joined(separator: "\n")
                                        let provider = NSItemProvider()
                                        provider.registerDataRepresentation(forTypeIdentifier: mediaIDsPasteboardType, visibility: .all) { completion in
                                            completion(text.data(using: .utf8), nil)
                                            return nil
                                        }
                                        return provider
                                    }
                            }
                        }
                        .padding(16)
                    }
                } else {
                    if !library.recentSongs.isEmpty {
                        recentlyPlayedRow
                    }
                    List(filtered, selection: $selectedIDs) { song in
                MusicRow(song: song, isPlaying: player.current?.id == song.id && player.isPlaying, isSelected: selectedIDs.contains(song.id))
                    .contentShape(Rectangle())
                    .onTapGesture {

                        let flags = NSEvent.modifierFlags
                        guard !flags.contains(.command) && !flags.contains(.shift) else { return }
                        player.play(song, in: filtered)
                    }
                    .onDrag {

                        let ids = selectedIDs.contains(song.id) ? Array(selectedIDs) : [song.id]
                        let text = ids.map { $0.uuidString }.joined(separator: "\n")
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: mediaIDsPasteboardType, visibility: .all) { completion in
                            completion(text.data(using: .utf8), nil)
                            return nil
                        }
                        return provider
                    }
                    .contextMenu {
                        Button("Edit metadata…") { selectedSong = song }
                        Button("Fetch metadata from the web") { fetchOne(song) }
                        Menu("Move to Playlist") {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) {

                                    if selectedIDs.contains(song.id) && selectedIDs.count > 1 {
                                        library.moveItems(withIDs: Array(selectedIDs), to: playlist)
                                        selectedIDs.removeAll()
                                    } else {
                                        library.moveItems(withIDs: [song.id], to: playlist)
                                    }
                                }
                            }
                            Button("New Playlist…") {
                                pendingAddSong = song
                                showingNewPlaylist = true
                            }
                        }
                        Button(selectedIDs.contains(song.id) && selectedIDs.count > 1 ? "Delete \(selectedIDs.count) selected…" : "Delete…", role: .destructive) {
                            itemsToDelete = selectedIDs.contains(song.id) && selectedIDs.count > 1
                                ? library.songs.filter { selectedIDs.contains($0.id) }
                                : [song]
                            showingDeleteConfirm = true
                        }
                    }
            }
            .listStyle(.plain)

            .scrollContentBackground(.hidden)
            .onReceive(library.$songs) { _ in

                let visible = Set(library.musicSongs.map { $0.id })
                selectedIDs.formIntersection(visible)
            }
            .onReceive(library.$playlists) { _ in

                let visible = Set(library.musicSongs.map { $0.id })
                selectedIDs.formIntersection(visible)
            }
                }
            }
        }

        .alert("Delete \(itemsToDelete.count == 1 ? "“\(itemsToDelete.first?.displayTitle ?? "")”" : "\(itemsToDelete.count) songs")?", isPresented: $showingDeleteConfirm) {
            Button("Move to Trash", role: .destructive) {
                let result = library.delete(itemsToDelete)
                if result.failed > 0 {
                    deleteNote = "\(result.failed) file\(result.failed == 1 ? "" : "s") could not be moved to the Trash — \(result.failed == 1 ? "it is" : "they are") still in the library."
                }
                itemsToDelete = []
                selectedIDs.removeAll()
            }
            Button("Cancel", role: .cancel) { itemsToDelete = [] }
        } message: {
            Text("The file\(itemsToDelete.count == 1 ? "" : "s") will be moved to the Trash. You can get \(itemsToDelete.count == 1 ? "it" : "them") back from the Trash.")
        }
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let created = library.createPlaylist(name: name)
                newPlaylistName = ""
                if let song = pendingAddSong {

                    if selectedIDs.contains(song.id) && selectedIDs.count > 1 {
                        library.moveItems(withIDs: Array(selectedIDs), to: created)
                        selectedIDs.removeAll()
                    } else {
                        library.moveItems(withIDs: [song.id], to: created)
                    }
                    pendingAddSong = nil
                }
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
                pendingAddSong = nil
            }
        }
    }

    private var recentlyPlayedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Played")
                .font(.headline)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(library.recentSongs) { song in
                        Button(action: { player.play(song, in: library.musicSongs) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Group {

                                    if !song.artworkPath.isEmpty, let image = ImageCache.shared.image(at: song.artworkPath, maxDimension: 180) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Image(systemName: "music.note")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(width: 90, height: 90)
                                .cornerRadius(10)
                                Text(song.displayTitle)
                                    .font(.caption)
                                    .bold()
                                    .lineLimit(1)
                                Text(song.displayCreator)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 90, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            Divider()
        }
    }

    private func albumDetailView(_ album: (name: String, songs: [MediaItem])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { selectedAlbum = nil }) {
                    Label("Back to Albums", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .bigGlassButton(cornerRadius: 12)
                Spacer()
                Button("Play All") {
                    if let first = album.songs.first {
                        player.play(first, in: album.songs)
                    }
                }
                .buttonStyle(.plain)
                .bigGlassButton(cornerRadius: 12)
            }
            .padding(16)
            Text(album.name)
                .font(.title2)
                .bold()
                .padding(.horizontal, 16)
            Text("\(album.songs.first?.displayCreator ?? "Unknown Artist") · \(album.songs.count) songs")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            if !selectedIDs.isEmpty {
                HStack {
                    Text("\(selectedIDs.count) selected")
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    Menu("Move to Playlist") {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.name) {
                                library.moveItems(withIDs: Array(selectedIDs), to: playlist)
                                selectedIDs.removeAll()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    Button("Delete", role: .destructive) {
                        itemsToDelete = library.songs.filter { selectedIDs.contains($0.id) }
                        showingDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    Button("Clear") { selectedIDs.removeAll() }
                        .buttonStyle(.plain)
                        .bigGlassButton(cornerRadius: 10)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            List(album.songs, selection: $selectedIDs) { song in
                MusicRow(song: song, isPlaying: player.current?.id == song.id && player.isPlaying, isSelected: selectedIDs.contains(song.id))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let flags = NSEvent.modifierFlags
                        guard !flags.contains(.command) && !flags.contains(.shift) else { return }
                        player.play(song, in: album.songs)
                    }
                    .onDrag {
                        let ids = selectedIDs.contains(song.id) ? Array(selectedIDs) : [song.id]
                        let text = ids.map { $0.uuidString }.joined(separator: "\n")
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: mediaIDsPasteboardType, visibility: .all) { completion in
                            completion(text.data(using: .utf8), nil)
                            return nil
                        }
                        return provider
                    }
                    .contextMenu {
                        Button("Edit metadata…") { selectedSong = song }
                        Button("Fetch metadata from the web") { fetchOne(song) }
                        Menu("Move to Playlist") {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) {
                                    if selectedIDs.contains(song.id) && selectedIDs.count > 1 {
                                        library.moveItems(withIDs: Array(selectedIDs), to: playlist)
                                        selectedIDs.removeAll()
                                    } else {
                                        library.moveItems(withIDs: [song.id], to: playlist)
                                    }
                                }
                            }
                            Button("New Playlist…") {
                                pendingAddSong = song
                                showingNewPlaylist = true
                            }
                        }
                        Button(selectedIDs.contains(song.id) && selectedIDs.count > 1 ? "Delete \(selectedIDs.count) selected…" : "Delete…", role: .destructive) {
                            itemsToDelete = selectedIDs.contains(song.id) && selectedIDs.count > 1
                                ? library.songs.filter { selectedIDs.contains($0.id) }
                                : [song]
                            showingDeleteConfirm = true
                        }
                    }
            }
            .listStyle(.plain)

            .scrollContentBackground(.hidden)
        }
    }

    private func fetchMissing() {
        let blanks = library.musicSongs.filter { $0.title.isEmpty || $0.creator.isEmpty }
        guard !blanks.isEmpty else { return }
        fetchingMissing = true
        Task {
            for (index, song) in blanks.enumerated() {
                await MainActor.run { fetchProgress = "\(index + 1)/\(blanks.count)" }

                let fetched = await MetadataService.fetchSong(for: song)
                _ = await LibraryStore.shared.applyFetched(fetched, to: song)

                try? await Task.sleep(nanoseconds: 1_100_000_000)
            }
            await MainActor.run {
                fetchingMissing = false
                fetchProgress = ""
            }
        }
    }

    private func fetchMissingLyrics() {
        let targets = library.musicSongs.filter { !$0.title.isEmpty && $0.syncedLyrics.isEmpty }
        guard !targets.isEmpty else { return }
        fetchingLyrics = true
        Task {
            for (index, song) in targets.enumerated() {
                await MainActor.run { lyricsProgress = "\(index + 1)/\(targets.count)" }
                let fetched = await MetadataService.fetchSong(for: song)
                _ = await LibraryStore.shared.applyFetched(fetched, to: song)
                try? await Task.sleep(nanoseconds: 1_100_000_000)
            }
            await MainActor.run {
                fetchingLyrics = false
                lyricsProgress = ""
            }
        }
    }

    private func fetchOne(_ song: MediaItem) {
        Task {
            let fetched = await MetadataService.fetchSong(for: song)
            _ = await LibraryStore.shared.applyFetched(fetched, to: song)
        }
    }
}

struct MusicRow: View {
    let song: MediaItem
    let isPlaying: Bool
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Group {

                if !song.artworkPath.isEmpty, let image = ImageCache.shared.image(at: song.artworkPath, maxDimension: 96) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.subheadline)
                    .bold(isPlaying)
                Text(song.displayCreator + (song.album.isEmpty ? "" : " — \(song.album)"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !song.releaseYear.isEmpty {
                Text(song.releaseYear)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(song.duration.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
            if song.title.isEmpty || song.creator.isEmpty {
                Text("Blank")
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.orange)
            }
            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 6)

        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(8)
    }
}

struct PlaylistVideoRow: View {
    let item: MediaItem
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "film")
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.subheadline)
                Text(item.kind == .movie ? "Movie" : "Video")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !item.playable {
                Text("\(item.url.pathExtension.uppercased()) — not playable")
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.orange)
            }
            Text(item.duration.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(8)
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerManager
    let playlist: Playlist
    @State private var selectedIDs: Set<MediaItem.ID> = []
    @State private var itemsToDelete: [MediaItem] = []
    @State private var showingDeleteConfirm = false
    @State private var deleteNote = ""
    @State private var selectedMovie: MediaItem?
    @State private var showingMoviePlayer = false
    @State private var editingSong: MediaItem?

    var body: some View {

        let current = library.playlists.first(where: { $0.id == playlist.id }) ?? playlist

        let items = library.items(for: current)
        let songs = items.filter { $0.kind == .song }
        let movieCount = items.filter { $0.kind == .movie }.count
        let videoCount = items.filter { $0.kind == .video }.count
        VStack(spacing: 0) {
            HStack {
                Text(current.name)
                    .font(.title2)
                    .bold()
                Spacer()
                Text("\(items.count) item\(items.count == 1 ? "" : "s")\(songs.isEmpty ? "" : " · \(songs.count) songs")\(movieCount == 0 ? "" : " · \(movieCount) movies")\(videoCount == 0 ? "" : " · \(videoCount) videos")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Play All") {
                    if let first = songs.first {
                        player.play(first, in: songs)
                    }
                }
                .buttonStyle(.plain)
                .bigGlassButton(cornerRadius: 12)
                .disabled(songs.isEmpty)
            }
            .padding(16)
            if !deleteNote.isEmpty {
                Text(deleteNote)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            if !selectedIDs.isEmpty {
                HStack {
                    Text("\(selectedIDs.count) selected")
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    Button("Remove from Playlist") {
                        library.removeItemsFromPlaylists(ids: Array(selectedIDs))
                        selectedIDs.removeAll()
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    Button("Delete", role: .destructive) {
                        itemsToDelete = items.filter { selectedIDs.contains($0.id) }
                        showingDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    Button("Clear") { selectedIDs.removeAll() }
                        .buttonStyle(.plain)
                        .bigGlassButton(cornerRadius: 10)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            if items.isEmpty {
                Text("Nothing here yet — right-click a song, movie or video and choose Move to Playlist, or drag it onto this playlist in the sidebar.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(items, selection: $selectedIDs) { item in
                    Group {
                        if item.kind == .song {
                            MusicRow(song: item, isPlaying: player.current?.id == item.id && player.isPlaying, isSelected: selectedIDs.contains(item.id))
                        } else {
                            PlaylistVideoRow(item: item, isSelected: selectedIDs.contains(item.id))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let flags = NSEvent.modifierFlags
                        guard !flags.contains(.command) && !flags.contains(.shift) else { return }
                        if item.kind == .song {
                            player.play(item, in: songs)
                        } else if item.playable {
                            selectedMovie = item
                            showingMoviePlayer = true
                        }
                    }
                    .onDrag {
                        let ids = selectedIDs.contains(item.id) ? Array(selectedIDs) : [item.id]
                        let text = ids.map { $0.uuidString }.joined(separator: "\n")
                        let provider = NSItemProvider()
                        provider.registerDataRepresentation(forTypeIdentifier: mediaIDsPasteboardType, visibility: .all) { completion in
                            completion(text.data(using: .utf8), nil)
                            return nil
                        }
                        return provider
                    }
                    .contextMenu {
                        if item.kind == .song {
                            Button("Edit metadata…") { editingSong = item }
                            Button("Fetch metadata from the web") {
                                Task {
                                    let fetched = await MetadataService.fetchSong(for: item)
                                    _ = await LibraryStore.shared.applyFetched(fetched, to: item)
                                }
                            }
                        }
                        Menu("Move to Playlist") {
                            ForEach(library.playlists.filter { $0.id != current.id }) { target in
                                Button(target.name) {
                                    if selectedIDs.contains(item.id) && selectedIDs.count > 1 {
                                        library.moveItems(withIDs: Array(selectedIDs), to: target)
                                        selectedIDs.removeAll()
                                    } else {
                                        library.moveItems(withIDs: [item.id], to: target)
                                    }
                                }
                            }
                        }
                        Button("Remove from Playlist") {
                            library.removeItemsFromPlaylists(ids: [item.id])
                        }
                        Button(selectedIDs.contains(item.id) && selectedIDs.count > 1 ? "Delete \(selectedIDs.count) selected…" : "Delete…", role: .destructive) {
                            itemsToDelete = selectedIDs.contains(item.id) && selectedIDs.count > 1
                                ? items.filter { selectedIDs.contains($0.id) }
                                : [item]
                            showingDeleteConfirm = true
                        }
                    }
                }
                .listStyle(.plain)

                .scrollContentBackground(.hidden)
                .onReceive(library.$songs) { _ in
                    let visible = Set(library.items(for: current).map { $0.id })
                    selectedIDs.formIntersection(visible)
                }
                .onReceive(library.$playlists) { _ in
                    let visible = Set(library.items(for: current).map { $0.id })
                    selectedIDs.formIntersection(visible)
                }
                .onReceive(library.$movies) { _ in
                    let visible = Set(library.items(for: current).map { $0.id })
                    selectedIDs.formIntersection(visible)
                }
                .onReceive(library.$videos) { _ in
                    let visible = Set(library.items(for: current).map { $0.id })
                    selectedIDs.formIntersection(visible)
                }
                .alert("Delete \(itemsToDelete.count == 1 ? "“\(itemsToDelete.first?.displayTitle ?? "")”" : "\(itemsToDelete.count) items")?", isPresented: $showingDeleteConfirm) {
                    Button("Move to Trash", role: .destructive) {
                        let result = library.delete(itemsToDelete)
                        if result.failed > 0 {
                            deleteNote = "\(result.failed) file\(result.failed == 1 ? "" : "s") could not be moved to the Trash — \(result.failed == 1 ? "it is" : "they are") still in the library."
                        }
                        itemsToDelete = []
                        selectedIDs.removeAll()
                    }
                    Button("Cancel", role: .cancel) { itemsToDelete = [] }
                } message: {
                    Text("The file\(itemsToDelete.count == 1 ? "" : "s") will be moved to the Trash. You can get \(itemsToDelete.count == 1 ? "it" : "them") back from the Trash.")
                }
                .sheet(isPresented: $showingMoviePlayer) {
                    if let movie = selectedMovie {
                        MoviePlayerView(movie: movie)
                    }
                }
                .sheet(item: $editingSong) { song in
                    MetadataEditorView(item: song)
                }
            }
        }
    }
}

struct VideoGridView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerManager
    let title: String
    let items: [MediaItem]
    @Binding var searchText: String
    @Binding var selectedMovie: MediaItem?
    @Binding var showingPlayer: Bool
    @State private var selectedIDs: Set<MediaItem.ID> = []
    @State private var lastClickedIndex: Int?
    @State private var itemsToDelete: [MediaItem] = []
    @State private var showingDeleteConfirm = false
    @State private var deleteNote = ""
    @State private var pendingNewPlaylistItem: MediaItem?
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""

    var filtered: [MediaItem] {
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter { $0.displayTitle.lowercased().contains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2)
                        .bold()
                    Text("\(items.count) \(title.lowercased())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .liquidGlass(cornerRadius: 18)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            HStack {
                Button("Select All") {
                    selectedIDs = Set(filtered.map { $0.id })
                    lastClickedIndex = nil
                }
                .keyboardShortcut("a", modifiers: .command)
                .buttonStyle(.plain)
                .bigGlassButton(cornerRadius: 10)
                if !selectedIDs.isEmpty {
                    Text("\(selectedIDs.count) selected")
                        .font(.subheadline)
                        .bold()
                    Spacer()
                    Button("Delete", role: .destructive) {
                        itemsToDelete = items.filter { selectedIDs.contains($0.id) }
                        showingDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 10)
                    Button("Clear") { selectedIDs.removeAll() }
                        .buttonStyle(.plain)
                        .bigGlassButton(cornerRadius: 10)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Text("Tip: drag movies or videos onto a playlist in the sidebar to move them there.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            if !deleteNote.isEmpty {
                Text(deleteNote)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filtered) { movie in
                        MovieCard(movie: movie, isSelected: selectedIDs.contains(movie.id))
                            .onTapGesture {
                                handleTap(on: movie)
                            }
                            .onDrag {

                                let ids = selectedIDs.contains(movie.id) ? Array(selectedIDs) : [movie.id]
                                let text = ids.map { $0.uuidString }.joined(separator: "\n")
                                let provider = NSItemProvider()
                                provider.registerDataRepresentation(forTypeIdentifier: mediaIDsPasteboardType, visibility: .all) { completion in
                                    completion(text.data(using: .utf8), nil)
                                    return nil
                                }
                                return provider
                            }
                            .contextMenu {
                                Menu("Move to Playlist") {
                                    ForEach(library.playlists) { playlist in
                                        Button(playlist.name) {
                                            if selectedIDs.contains(movie.id) && selectedIDs.count > 1 {
                                                library.moveItems(withIDs: Array(selectedIDs), to: playlist)
                                                selectedIDs.removeAll()
                                            } else {
                                                library.moveItems(withIDs: [movie.id], to: playlist)
                                            }
                                        }
                                    }
                                    Button("New Playlist…") {
                                        pendingNewPlaylistItem = movie
                                        showingNewPlaylist = true
                                    }
                                }
                                Button(selectedIDs.contains(movie.id) && selectedIDs.count > 1 ? "Delete \(selectedIDs.count) selected…" : "Delete…", role: .destructive) {
                                    itemsToDelete = selectedIDs.contains(movie.id) && selectedIDs.count > 1
                                        ? items.filter { selectedIDs.contains($0.id) }
                                        : [movie]
                                    showingDeleteConfirm = true
                                }
                            }
                    }
                }
                .padding(16)
            }
        }
        .alert("Delete \(itemsToDelete.count == 1 ? "“\(itemsToDelete.first?.displayTitle ?? "")”" : "\(itemsToDelete.count) \(items.first?.kind == .movie ? "movies" : "videos")")?", isPresented: $showingDeleteConfirm) {
            Button("Move to Trash", role: .destructive) {
                let result = library.delete(itemsToDelete)
                if result.failed > 0 {
                    deleteNote = "\(result.failed) file\(result.failed == 1 ? "" : "s") could not be moved to the Trash — \(result.failed == 1 ? "it is" : "they are") still in the library."
                }
                itemsToDelete = []
                selectedIDs.removeAll()
            }
            Button("Cancel", role: .cancel) { itemsToDelete = [] }
        } message: {
            Text("The file\(itemsToDelete.count == 1 ? "" : "s") will be moved to the Trash. You can get \(itemsToDelete.count == 1 ? "it" : "them") back from the Trash.")
        }
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let created = library.createPlaylist(name: name)
                newPlaylistName = ""
                if let item = pendingNewPlaylistItem {
                    if selectedIDs.contains(item.id) && selectedIDs.count > 1 {
                        library.moveItems(withIDs: Array(selectedIDs), to: created)
                        selectedIDs.removeAll()
                    } else {
                        library.moveItems(withIDs: [item.id], to: created)
                    }
                    pendingNewPlaylistItem = nil
                }
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
                pendingNewPlaylistItem = nil
            }
        }
        .onReceive(library.$playlists) { _ in

            let visible = Set(items.map { $0.id })
            selectedIDs.formIntersection(visible)
        }
        .onReceive(library.$movies) { _ in
            let visible = Set(items.map { $0.id })
            selectedIDs.formIntersection(visible)
        }
        .onReceive(library.$videos) { _ in
            let visible = Set(items.map { $0.id })
            selectedIDs.formIntersection(visible)
        }
    }

    private func handleTap(on movie: MediaItem) {
        guard let index = filtered.firstIndex(where: { $0.id == movie.id }) else { return }
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedIDs.contains(movie.id) {
                selectedIDs.remove(movie.id)
            } else {
                selectedIDs.insert(movie.id)
            }
            lastClickedIndex = index
        } else if flags.contains(.shift) {
            let start = lastClickedIndex ?? index
            let lo = min(start, index)
            let hi = max(start, index)
            for item in filtered[lo...hi] {
                selectedIDs.insert(item.id)
            }
            lastClickedIndex = index
        } else {
            selectedIDs.removeAll()
            lastClickedIndex = index
            if movie.playable {
                selectedMovie = movie
                showingPlayer = true
            }
        }
    }
}

struct MovieCard: View {
    @EnvironmentObject var library: LibraryStore
    let movie: MediaItem
    var isSelected: Bool = false
    @State private var thumbPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image = thumbImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                } else {
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
                    .aspectRatio(16 / 9, contentMode: .fill)
                }
            }
            .cornerRadius(12)
            .overlay(alignment: .bottomTrailing) {
                if !movie.playable {
                    Text("\(movie.url.pathExtension.uppercased()) — not playable")
                        .font(.caption2)
                        .bold()
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .padding(6)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .background(Color.white)
                        .clipShape(Circle())
                        .padding(6)
                }
            }
            Text(movie.displayTitle)
                .font(.subheadline)
                .bold()
                .lineLimit(1)
            HStack {
                if movie.lastPosition > 5 {
                    Text("Resume \(movie.lastPosition.formattedDuration)")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                Spacer()
                Text(movie.duration.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)

        .liquidGlass(cornerRadius: 16)
        .onAppear {
            if thumbPath.isEmpty {

                Task {
                    thumbPath = await library.loadThumbnail(for: movie)
                }
            }
        }
    }

    private var thumbImage: NSImage? {
        let path = thumbPath.isEmpty ? movie.artworkPath : thumbPath
        guard !path.isEmpty else { return nil }

        return ImageCache.shared.image(at: path, maxDimension: 480)
    }
}

struct AlbumCard: View {
    let name: String
    let songs: [MediaItem]
    @State private var cover: NSImage?

    private var coverKey: String {
        songs.compactMap { $0.artworkPath.isEmpty ? nil : $0.artworkPath }.first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let cover = cover {
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "square.stack")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 140, height: 140)
            .cornerRadius(12)
            .shadow(radius: 6)
            Text(name)
                .font(.subheadline)
                .bold()
                .lineLimit(1)
            Text("\(songs.first?.displayCreator ?? "Unknown Artist") · \(songs.count) songs")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 140, alignment: .leading)
        .padding(10)

        .liquidGlass(cornerRadius: 16)
        .task(id: coverKey) {
            for song in songs {

                if !song.artworkPath.isEmpty, let image = ImageCache.shared.image(at: song.artworkPath, maxDimension: 280) {
                    cover = image
                    return
                }
            }
            for song in songs {

                let path = await LibraryStore.shared.loadThumbnail(for: song)
                if !path.isEmpty, let image = ImageCache.shared.image(at: path, maxDimension: 280) {
                    cover = image
                    return
                }
            }
        }
    }
}

struct VisualizerView: View {
    let level: Float
    @State private var phase: Double = 0
    private let timer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.primary)
                    .frame(width: 3, height: barHeight(i))
            }
        }
        .frame(height: 20, alignment: .bottom)
        .onReceive(timer) { _ in phase += 0.55 }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let wobble = 0.55 + 0.45 * sin(phase + Double(i) * 1.4)
        return 3 + CGFloat(level) * CGFloat(wobble) * 16
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var player: PlayerManager
    @State private var showingLyrics = false
    @State private var showingFullPage = false
    @State private var volume: Float = 1.0

    var body: some View {

        HStack(spacing: 10) {
            Group {

                if let item = player.current, !item.artworkPath.isEmpty,
                   let image = ImageCache.shared.image(at: item.artworkPath, maxDimension: 88) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: player.current?.kind == .song ? "music.note" : "film")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .cornerRadius(8)
            if player.current != nil {
                VisualizerView(level: player.audioLevel)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.displayTitle ?? "Nothing playing")
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                Text(player.current?.displayCreator ?? "Pick a song or a movie")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)

            .contentShape(Rectangle())
            .onTapGesture {
                if player.current != nil { showingFullPage = true }
            }

            Button(action: { player.playPrevious() }) {
                Label("Previous", systemImage: "backward.fill")
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            Button(action: { player.togglePlayPause() }) {
                Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            }
            .buttonStyle(.plain)
            .playGlassButton(cornerRadius: 14)
            Button(action: { player.playNext() }) {
                Label("Next", systemImage: "forward.fill")
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)

            VStack(spacing: 2) {
                Slider(value: Binding(
                    get: { player.position },
                    set: { player.seek(to: $0) }
                ), in: 0...(max(player.duration, 1)))
                .frame(maxWidth: 220)
                HStack {
                    Text(player.position.formattedDuration)
                    Spacer()
                    Text(player.duration.formattedDuration)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { player.shuffle() }) {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            .disabled(player.queue.isEmpty)

            if player.current?.kind == .song, !(player.current?.lyrics.isEmpty ?? true) {
                Button("Lyrics") { showingLyrics.toggle() }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 12)
            }

            RoutePickerView()
                .frame(width: 30, height: 30)
                .padding(3)
                .contentShape(Rectangle())
                .onTapGesture {}
                .highPriorityGesture(TapGesture().onEnded {})

            Button(action: { if player.current != nil { showingFullPage = true } }) {
                Label("Full page", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .bigGlassButton(cornerRadius: 12)
            .disabled(player.current == nil)
            Slider(value: Binding(get: { Double(volume) }, set: { volume = Float($0); player.setVolume(volume) }), in: 0...1)
                .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 0)
        .sheet(isPresented: $showingLyrics) {
            if let song = player.current {
                LyricsView(item: song, position: player.position)
            }
        }
        .sheet(isPresented: $showingFullPage) {
            NowPlayingFullView()
        }
    }
}

struct RoutePickerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {

        AVRoutePickerView()
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

struct NowPlayingFullView: View {
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var glowColors: [Color] = [.indigo, .teal, .purple]
    @State private var drift = false

    var body: some View {
        ZStack {

            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            ForEach(Array(glowColors.enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(color)
                    .frame(width: 420, height: 420)
                    .blur(radius: 70)
                    .opacity(0.30 + Double(player.audioLevel) * 0.45)
                    .scaleEffect(1 + Double(player.audioLevel) * 0.12)
                    .offset(x: blobOffset(index).x, y: blobOffset(index).y)
                    .animation(.easeOut(duration: 0.15), value: player.audioLevel)
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {

                    Button(action: { dismiss() }) {
                        Label("Close", systemImage: "xmark")
                            .font(.headline)
                            .bold()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassButton(cornerRadius: 20)
                    Spacer()
                }
                Group {

                    if let item = player.current, !item.artworkPath.isEmpty,
                       let image = ImageCache.shared.image(at: item.artworkPath, maxDimension: 600) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 120))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 300, height: 300)
                .cornerRadius(20)
                .shadow(radius: 20)
                VStack(spacing: 4) {
                    Text(player.current?.displayTitle ?? "Nothing playing")
                        .font(.title)
                        .bold()
                        .lineLimit(1)
                    Text(player.current?.displayCreator ?? "")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let album = player.current?.album, !album.isEmpty {
                        Text(album)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { player.position },
                        set: { player.seek(to: $0) }
                    ), in: 0...(max(player.duration, 1)))
                    HStack {
                        Text(player.position.formattedDuration)
                        Spacer()
                        Text(player.duration.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: 480)
                HStack(spacing: 12) {
                    Button(action: { player.shuffle() }) {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 14)
                    .disabled(player.queue.isEmpty)
                    Button(action: { player.playPrevious() }) {
                        Label("Previous", systemImage: "backward.fill")
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 14)
                    Button(action: { player.togglePlayPause() }) {
                        Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .playGlassButton(cornerRadius: 16)
                    Button(action: { player.playNext() }) {
                        Label("Next", systemImage: "forward.fill")
                    }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 14)
                }
                if let item = player.current, item.kind == .song {
                    SyncedLyricsView(item: item, position: player.position)
                        .frame(maxWidth: 560, maxHeight: 220)
                        .clipped()
                }
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 760)
        .onAppear {
            refreshGlowColors()
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .onChange(of: player.current?.id) { refreshGlowColors() }
    }

    private func blobOffset(_ index: Int) -> (x: CGFloat, y: CGFloat) {
        let d: CGFloat = drift ? 40 : -40
        switch index % 3 {
        case 0: return (x: -180 + d, y: -220 - d)
        case 1: return (x: 200 - d, y: 180 + d)
        default: return (x: d, y: 240 - d)
        }
    }

    private func refreshGlowColors() {
        guard let item = player.current,
              !item.artworkPath.isEmpty,

              let image = ImageCache.shared.image(at: item.artworkPath, maxDimension: 64) else {
            glowColors = [.indigo, .teal, .purple]
            return
        }
        glowColors = ArtworkColors.extract(from: image)
    }
}

struct SyncedLyricsView: View {
    let item: MediaItem
    let position: Double
    @State private var lines: [LyricLine] = []

    private var currentLineID: UUID? {
        lines.last(where: { $0.time <= position })?.id
    }

    private func isCurrent(_ line: LyricLine) -> Bool {
        line.time <= position && (lines.first(where: { $0.time > line.time })?.time ?? .infinity) > position
    }

    var body: some View {
        Group {
            if !lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(lines) { line in
                                let current = isCurrent(line)
                                Text(line.text)

                                    .font(.title3)
                                    .bold(current)
                                    .foregroundColor(current ? .primary : .secondary)
                                    .opacity(current ? 1.0 : 0.45)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                    .id(line.id)
                                    .animation(.easeInOut(duration: 0.6), value: current)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        .padding(.vertical, 60)
                    }
                    .clipped()
                    .onChange(of: currentLineID) { _, id in
                        if let id = id {
                            withAnimation(.easeInOut(duration: 1.2)) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            } else if !item.lyrics.isEmpty {
                ScrollView {
                    Text(item.lyrics)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No lyrics for this song — LRCLIB had none. Try the metadata editor to fetch them again.")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            lines = LRCParser.parse(item.syncedLyrics)
        }
        .onChange(of: item.id) { lines = LRCParser.parse(item.syncedLyrics) }

        .onChange(of: item.syncedLyrics) { lines = LRCParser.parse(item.syncedLyrics) }
    }
}

struct LyricsView: View {
    let item: MediaItem
    let position: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.displayTitle)
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Label("Close", systemImage: "xmark")
                        .font(.subheadline)
                        .bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .liquidGlassButton(cornerRadius: 16)
            }
            Text(item.displayCreator)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Divider()
            SyncedLyricsView(item: item, position: position)
        }
        .padding(20)
        .frame(width: 420, height: 500)
    }
}

struct MoviePlayerView: View {
    @EnvironmentObject var player: PlayerManager
    @ObservedObject private var captionGen = CaptionGenerator.shared
    let movie: MediaItem
    @State private var cues: [CaptionCue] = []
    @State private var currentCaption = ""
    @State private var generating = false
    @State private var captionError = ""

    var body: some View {
        ZStack {
            PlayerView()
            VStack {
                Spacer()
                if !currentCaption.isEmpty {
                    Text(currentCaption)
                        .font(.title3)
                        .bold()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.65))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom, 48)
                        .padding(.horizontal, 40)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    if generating {
                        Text("Generating captions… \(Int(captionGen.progress * 100))%")
                            .font(.caption)
                            .padding(8)
                            .liquidGlass()
                    } else if cues.isEmpty {
                        Button("Generate captions") { generate() }
                            .buttonStyle(.plain)
                            .bigGlassButton(cornerRadius: 12)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            player.play(movie)
            loadCaptions()
        }
        .onDisappear { player.savePosition() }
        .onReceive(player.$position) { pos in
            currentCaption = cues.first(where: { pos >= $0.start && pos <= $0.end })?.text ?? ""
        }
    }

    private func loadCaptions() {
        if let cached = CaptionGenerator.shared.cachedCues(for: movie) {
            cues = cached
        } else if let sidecar = CaptionGenerator.shared.sidecarCues(for: movie) {
            cues = sidecar
        }
    }

    private func generate() {
        generating = true
        captionError = ""
        Task {
            let result = await CaptionGenerator.shared.generate(for: movie)
            await MainActor.run {
                generating = false
                if let result = result, !result.isEmpty {
                    cues = result
                } else {
                    captionError = CaptionGenerator.shared.lastError ?? "Could not generate captions for this movie."
                }
            }
        }
    }
}

struct PlayerView: NSViewRepresentable {
    @EnvironmentObject var player: PlayerManager

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player.player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

struct MetadataEditorView: View {
    @EnvironmentObject var library: LibraryStore
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var creator: String
    @State private var album: String
    @State private var genre: String
    @State private var releaseDate: String
    @State private var lyrics: String
    @State private var syncedLyrics: String
    @State private var lyricsTab = 0
    @State private var fetching = false
    @State private var fetchNote = ""
    @State private var fetchedArtworkURL: URL?

    init(item: MediaItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _creator = State(initialValue: item.creator)
        _album = State(initialValue: item.album)
        _genre = State(initialValue: item.genre)
        _releaseDate = State(initialValue: item.releaseDate)
        _lyrics = State(initialValue: item.lyrics)
        _syncedLyrics = State(initialValue: item.syncedLyrics)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Metadata — \(item.displayTitle)")
                .font(.headline)
            Text("Type the name and the creator, then Fetch. The app looks it up on the web (MusicBrainz + iTunes + LRCLIB, all free, no account) and fills in the rest automatically — album, release date, genre, artwork and lyrics.")
                .font(.caption)
                .foregroundColor(.secondary)

            Form {
                TextField("Song name", text: $title)
                TextField("Creator / artist", text: $creator)
                TextField("Album", text: $album)
                TextField("Genre", text: $genre)
                TextField("Release date", text: $releaseDate)
            }

            HStack {
                Button(fetching ? "Fetching…" : "Fetch from the web") { fetch() }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 12)
                    .disabled(fetching || title.isEmpty)

                Button("Apply") { applyEdits() }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 12)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .bigGlassButton(cornerRadius: 12)
            }
            if !fetchNote.isEmpty {
                Text(fetchNote)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Lyrics")
                .font(.subheadline)
                .bold()
            Picker("Lyrics", selection: $lyricsTab) {
                Text("Plain").tag(0)
                Text("Time-synced").tag(1)
            }
            .pickerStyle(.segmented)
            if lyricsTab == 0 {
                TextEditor(text: $lyrics)
                    .font(.body)
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3), width: 1)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("One line per time stamp: [mm:ss.xx] words")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $syncedLyrics)
                        .font(.body)
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.3), width: 1)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 520, height: 620)
    }

    private func fetch() {
        fetching = true
        fetchNote = ""
        Task {

            let fetched = await MetadataService.fetchSong(title: title, creator: creator, album: album)
            await MainActor.run {
                fetching = false
                if title.isEmpty, !fetched.title.isEmpty { title = fetched.title }
                if creator.isEmpty, !fetched.creator.isEmpty { creator = fetched.creator }
                if album.isEmpty, !fetched.album.isEmpty { album = fetched.album }
                if genre.isEmpty, !fetched.genre.isEmpty { genre = fetched.genre }
                if releaseDate.isEmpty, !fetched.releaseDate.isEmpty { releaseDate = fetched.releaseDate }
                if lyrics.isEmpty, !fetched.lyrics.isEmpty { lyrics = fetched.lyrics }
                if syncedLyrics.isEmpty, !fetched.syncedLyrics.isEmpty { syncedLyrics = fetched.syncedLyrics }
                var note = "Found"
                if !fetched.source.isEmpty { note += " via \(fetched.source)" }
                note += fetched.lyrics.isEmpty && fetched.syncedLyrics.isEmpty ? " — no lyrics available for this song." : " — lyrics included."
                if fetched.title.isEmpty && fetched.creator.isEmpty {
                    note = "Nothing found for that name and creator — check the spelling, or try a different creator."
                }
                fetchNote = note

                fetchedArtworkURL = fetched.artworkURL
            }
        }
    }

    private func currentItem() -> MediaItem {
        var updated = item
        updated.title = title
        updated.creator = creator
        updated.album = album
        updated.genre = genre
        updated.releaseDate = releaseDate
        updated.lyrics = lyrics
        updated.syncedLyrics = syncedLyrics
        updated.source = "web"
        return updated
    }

    private func applyEdits() {
        fetchNote = "Saving…"
        Task {
            var updated = currentItem()
            if let artURL = fetchedArtworkURL,
               let data = await MetadataService.downloadArtwork(artURL) {
                updated.artworkPath = LibraryStore.shared.saveArtworkData(data, for: updated)
            }
            LibraryStore.shared.update(updated)
            let written = await LibraryStore.shared.writeTagsToFile(updated)
            await MainActor.run {
                if written != nil {
                    fetchNote = "Saved — written into the file itself."
                } else if LibraryStore.shared.isLoadedInPlayer(updated) {
                    fetchNote = "Saved in the library — the file itself wasn't written because this song is playing right now. It will be written next time you save while it is stopped."
                } else if item.url.pathExtension.lowercased() == "m4a" {
                    fetchNote = "Saved in the library, but the file write did not work — the library copy still holds the tags."
                } else {
                    fetchNote = "Saved in the library. (Only M4A files can have their tags written into the file.)"
                }
            }
        }
    }
}

extension Double {
    var formattedDuration: String {
        guard isFinite, self > 0 else { return "0:00" }
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
