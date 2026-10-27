@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

final class CaptionGenerator: ObservableObject {
    static let shared = CaptionGenerator()

    @Published private(set) var generatingMovieID: UUID?
    @Published private(set) var progress: Double = 0
    @Published var lastError: String?

    private init() {}

    func cachedCues(for movie: MediaItem) -> [CaptionCue]? {
        let url = cacheURL(for: movie)
        guard let data = try? Data(contentsOf: url),
              let cues = try? JSONDecoder().decode([CaptionCue].self, from: data) else { return nil }
        return cues
    }

    private func cacheURL(for movie: MediaItem) -> URL {
        LibraryStore.captionsDirectory().appendingPathComponent(movie.id.uuidString + ".json")
    }

    private func saveCues(_ cues: [CaptionCue], for movie: MediaItem) {
        if let data = try? JSONEncoder().encode(cues) {
            try? data.write(to: cacheURL(for: movie))
        }
    }

    func sidecarCues(for movie: MediaItem) -> [CaptionCue]? {
        let srtURL = movie.url.deletingPathExtension().appendingPathExtension("srt")
        guard let text = try? String(contentsOf: srtURL, encoding: .utf8) else { return nil }
        return SRTParser.parse(text)
    }

    func generate(for movie: MediaItem, localeID: String = "en-US") async -> [CaptionCue]? {
        if let cached = cachedCues(for: movie) { return cached }
        if let sidecar = sidecarCues(for: movie) {
            saveCues(sidecar, for: movie)
            return sidecar
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)),
              recognizer.isAvailable else {
            await MainActor.run {
                self.lastError = "Speech recognition is not available for \(localeID) on this Mac. Check System Settings > Keyboard > Dictation, or pick another language."
            }
            return nil
        }
        await MainActor.run {
            self.generatingMovieID = movie.id
            self.progress = 0
        }
        let cues = await transcribeMovie(movie, recognizer: recognizer)
        await MainActor.run {
            self.generatingMovieID = nil
            self.progress = 0
        }
        if let cues = cues, !cues.isEmpty {
            saveCues(cues, for: movie)
        }
        return cues
    }

    private func transcribeMovie(_ movie: MediaItem, recognizer: SFSpeechRecognizer) async -> [CaptionCue]? {
        let asset = AVAsset(url: movie.url)
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let total = movie.duration
        var allCues: [CaptionCue] = []
        let chunkLength = 40.0
        var start = 0.0
        while start < total {
            let length = min(chunkLength, total - start)
            let cues = await transcribeChunk(asset: asset, track: audioTrack, start: start, length: length, recognizer: recognizer)
            allCues.append(contentsOf: cues)
            start += length
            let done = start / total
            await MainActor.run { self.progress = done }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return allCues
    }

    private func transcribeChunk(asset: AVAsset, track: AVAssetTrack, start: Double, length: Double, recognizer: SFSpeechRecognizer) async -> [CaptionCue] {
        await withCheckedContinuation { continuation in
            let reader: AVAssetReader
            do {
                reader = try AVAssetReader(asset: asset)
            } catch {
                continuation.resume(returning: [])
                return
            }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1
            ])

            reader.add(output)
            let startTime = CMTime(seconds: start, preferredTimescale: 600)
            let duration = CMTime(seconds: length, preferredTimescale: 600)
            reader.timeRange = CMTimeRange(start: startTime, duration: duration)
            guard reader.startReading() else {
                continuation.resume(returning: [])
                return
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = true
            var cues: [CaptionCue] = []
            var finished = false
            let finishOnce: ([CaptionCue]) -> Void = { result in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: result)
            }
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    for segment in result.bestTranscription.segments {
                        let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { continue }
                        cues.append(CaptionCue(
                            start: start + segment.timestamp,
                            end: start + segment.timestamp + segment.duration,
                            text: text
                        ))
                    }
                    finishOnce(cues)
                } else if error != nil {
                    finishOnce(cues)
                }
            }

            let readerBox = SendableBox(reader)
            let outputBox = SendableBox(output)
            let requestBox = SendableBox(request)
            let taskBox = SendableBox(task)
            let finishBox = SendableBox(finishOnce)
            DispatchQueue.global(qos: .userInitiated).async {
                let reader = readerBox.value
                let output = outputBox.value
                let request = requestBox.value
                while reader.status == .reading {
                    guard let sample = output.copyNextSampleBuffer() else { break }
                    request.appendAudioSampleBuffer(sample)
                }
                request.endAudio()

                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    taskBox.value.cancel()
                    finishBox.value(cues)
                }
            }
        }
    }
}

enum SRTParser {
    static func parse(_ text: String) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: .newlines).filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }

            let times = lines[1].components(separatedBy: " --> ")
            guard times.count == 2,
                  let start = parseTime(times[0]),
                  let end = parseTime(times[1]) else { continue }
            let caption = lines.dropFirst(2).joined(separator: "\n")
            cues.append(CaptionCue(start: start, end: end, text: caption))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTime(_ s: String) -> Double? {

        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 3 else { return nil }
        let secParts = parts[2].split(separator: ",")
        guard let h = Double(parts[0]), let m = Double(parts[1]),
              let sec = Double(secParts[0]) else { return nil }
        var total = h * 3600 + m * 60 + sec
        if secParts.count > 1, let ms = Double(secParts[1]) {
            total += ms / 1000
        }
        return total
    }
}

final class SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
