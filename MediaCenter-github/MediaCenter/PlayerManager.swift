import AppKit
import AVFoundation
import AVKit
import Combine
import Foundation

final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published private(set) var current: MediaItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var queue: [MediaItem] = []

    @Published private(set) var audioLevel: Float = 0

    let player = AVPlayer()
    private var timeObserver: Any?
    private var itemObserver: NSObjectProtocol?
    private var exitObserver: NSObjectProtocol?
    private var lastToggle = Date.distantPast
    private var lastSavedPosition: Double = -1
    private let levelTap = AudioLevelTap()
    private var levelTimer: Timer?

    private init() {
        player.allowsExternalPlayback = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.position = time.seconds
            self.isPlaying = self.player.rate > 0
        }
        itemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
                self?.playNext()
            }

        exitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
                LibraryStore.shared.saveExitSession()
            }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isPlaying {
                self.audioLevel = max(AudioLevelTap.rawLevel, self.audioLevel * 0.82)
            } else {
                self.audioLevel *= 0.7
                if self.audioLevel < 0.01 { self.audioLevel = 0 }
            }
        }
    }

    func play(_ item: MediaItem, in list: [MediaItem]? = nil) {
        guard item.playable else { return }
        if let list = list {
            queue = list
        }

        if current?.id == item.id, player.currentItem != nil {
            if position >= duration - 1 { seek(to: 0) }
            player.play()
            isPlaying = true
            return
        }
        savePosition()
        current = item
        duration = item.duration
        lastSavedPosition = item.lastPosition
        let avItem = AVPlayerItem(url: item.url)
        player.replaceCurrentItem(with: avItem)

        if item.lastPosition > 5, item.lastPosition < item.duration - 10 {
            player.seek(to: CMTime(seconds: item.lastPosition, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true

        if item.kind == .song {
            LibraryStore.shared.markPlayed(item)
        }
        Task { await levelTap.attach(to: avItem) }
    }

    func togglePlayPause() {

        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.15 else { return }
        lastToggle = now
        if player.rate > 0 {
            player.pause()
            isPlaying = false
            savePosition()
        } else {
            player.play()
            isPlaying = true
        }
    }

    func refreshCurrent(_ item: MediaItem) {
        guard current?.id == item.id else { return }
        current = item
    }

    func shuffle() {
        guard !queue.isEmpty else { return }
        queue.shuffle()
        if let first = queue.first {
            play(first)
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        position = 0
        current = nil
    }

    func removeFromQueue(_ item: MediaItem) {
        queue.removeAll { $0.id == item.id }
    }

    func playNext() {
        guard let current = current,
              let index = queue.firstIndex(where: { $0.id == current.id }),
              index + 1 < queue.count else {
            savePosition()
            isPlaying = false
            return
        }
        play(queue[index + 1])
    }

    func playPrevious() {
        guard let current = current,
              let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        if position > 5 {
            seek(to: 0)
            return
        }
        if index > 0 { play(queue[index - 1]) }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    func setVolume(_ value: Float) {
        player.volume = value
    }

    func savePosition() {
        guard let current = current else { return }
        guard current.kind != .song else { return }
        guard abs(position - lastSavedPosition) > 2 else { return }
        lastSavedPosition = position
        var updated = current
        updated.lastPosition = position
        LibraryStore.shared.update(updated)
        self.current = updated
    }
}
