import AVFoundation
import CoreAudio
import CoreMedia

final class AudioLevelTap {

    static var rawLevel: Float = 0

    static var tapIsFloat = true

    private var tap: MTAudioProcessingTap?

    @MainActor
    func attach(to item: AVPlayerItem) async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: { _, _, _ in },
            finalize: { _ in },
            prepare: { _, _, format in
                let flags = format.pointee.mFormatFlags
                AudioLevelTap.tapIsFloat = (flags & kAudioFormatFlagIsFloat) != 0
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in

                MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
                guard AudioLevelTap.tapIsFloat else { return }
                var peak: Float = 0
                for buffer in UnsafeMutableAudioBufferListPointer(bufferListInOut) {
                    guard let data = buffer.mData else { continue }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = data.assumingMemoryBound(to: Float.self)
                    for s in 0..<count {
                        let v = abs(samples[s])
                        if v > peak { peak = v }
                    }
                }
                AudioLevelTap.rawLevel = min(peak, 1)
            }
        )
        var newTap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &newTap)
        guard status == noErr, let newTap = newTap else { return }
        tap = newTap
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = newTap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }
}
