# Media Center - Technical Changelog

Impersonal build notes for the Beta 1.1 codebase. License: MIT.

## v2.1 - Colour, fixed buttons, lyrics scroll, AirPlay fix

- Gradient restored behind the whole app: indigo, pink, purple, teal. Deep in dark mode, pale in light mode. Liquid Glass stays clear, so colour shows through the glass.
- Action buttons fixed at 36pt tall, Play/Pause at 44pt tall, at any window size. First-open window fixed at 1100 x 700, minimum 1000 x 640. Bottom bar slimmed: narrower title and progress slider.
- Lyrics: every line stays the same size (.title3). Only brightness changes. No scaling, no glow swelling, no breathing. The list scrolls up to the current line in about 1.2 seconds. Lines wrap inside the box, with padding above and below so the current line can sit in the middle. Full-page lyrics bounded to maxHeight 220.
- AirPlay fix: the bar-wide tap gesture was removed. The full song page opens from the song title, artwork, or the "Full page" button. The AirPlay picker has its own padded 36pt hit area.
- Icon: Wave Bars style (teal/indigo gradient, pink/purple/white equaliser bars, white play symbol). Ten sizes installed in AppIcon.appiconset, verified against Contents.json.

## v2.0 - More formats, less memory, cleaner interface

- Formats added: audio MP3, M4A, AAC, Apple Lossless, FLAC, WAV, AIFF, CAF, MP2, M4B; video MP4, M4V, MOV, 3GP. Unplayable formats (MKV, AVI, WMV, MPG/MPEG, WebM, FLV, OGG, VOB, M2TS, MTS, DIVX) are still listed, with the format named on the card, for example "MPG - not playable".
- ImageCache.swift added: NSCache capped at 120 MB / 200 images, images downscaled to displayed size, saved artwork downscaled to 600px. Memory target: under 500 MB at peak. That figure is a build target, not a measured result. Verify in Activity Monitor while playing music and scrolling.
- Interface: clear glass headers for Movies/Videos, roomier rows, 48px covers, sidebar 240px.

## v1.9 - Karaoke lyrics

- Time-synced lyrics from LRCLIB, one timestamp per line. The current line is bright, other lines are dim.
- Lyrics live in the library only. No writable Apple identifier exists for lyrics, so lyrics are never written into audio files.

## v1.8 - Clear Liquid Glass, bigger labelled buttons, drag to playlists

- Clear glass throughout, bigger labelled buttons, drag songs, movies, and videos into playlists.

## v1.7 - Caption crash fix, colourful homepage

- Caption generation crash fixed: the audio reader stays alive for the whole job via a Sendable box, with a status check, and fails quietly instead of crashing.
- Colourful homepage with Liquid Glass gradient wash.

## v1.6 - Multi-select drag, movies in playlists, editable lyrics, smarter fetch

- Multi-select drag of songs into playlists, movies and videos in playlists, editable lyrics, smarter metadata fetch.

## v1.5 - Multi-select, drag to playlists, mass delete

- Multi-select with Cmd+A and Shift-click, drag to playlists, mass delete.

## v1.4 - Delete, resume, Exit, lyrics Close, import destinations

- Delete, resume only the last song, Exit, lyrics Close button, import destinations.

## v1.3 - Synced lyrics fix, album grid, song page

- Synced lyrics re-read on song change, album grid with big covers, song page with artwork-colour glows.

## v1.2 - Reliability fixes

- Player debounce 0.15s on play/pause toggle, main-thread library updates through a single funnel, merge by path then inode, cache saves coalesced at 0.5s.

## v1.1 - First Xcode error fixes

- Exhaustive switches, macOS 13 deprecation fixes, metadata genre read from the iTunes metadata loop, Sendable warnings fixed with @preconcurrency.

## v1.0 - First build

- SwiftUI front end, AVPlayer playback with queue and resume positions, metadata fetch (MusicBrainz, then iTunes, then LRCLIB lyrics), batch "Fill in blank songs" at MusicBrainz rate limit of 1 request per second, optional tag writing into M4A via passthrough export with backup then swap, movie captions from .srt sidecar first, otherwise on-device speech recognition in 40 second chunks cached as JSON, Liquid Glass via .glassEffect on macOS 26 with .ultraThinMaterial fallback, AVRoutePickerView for AirPlay/Bluetooth.
- Data: music and movies stay in place and are only read. App data lives in `~/Library/Application Support/MediaCenter/` (library.json, playlists.json, session.json, Artwork/, Captions/). Settings in UserDefaults. Nothing is stored inside the .app.

## Build

- Open `MediaCenter.xcodeproj` in Xcode. Cmd+B to build, Cmd+R to run.
- Hardened Runtime is enabled, with entitlements for network client and user-selected file read-write. Signing requires a team set in Xcode Signing and Capabilities. That step is outside the code.
- No comments in Swift source files, by design. No copyright comments in code. The MIT license lives in LICENSE at the repo root.
