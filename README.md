# Media Center - Beta 1.1

Media Center is a free, native macOS app for music and movies in one local library. No subscription, no account, and no cloud service in the middle. It points at folders on the Mac and plays the files already there.

The app is written in SwiftUI. Playback runs on AVPlayer, the library is stored in plain local JSON, and most heavy work happens on device.

> Beta 1.1 is an early version. The core works, and development is still active. Bugs can be reported in Issues.

## Download

Download `MediaCenter-1.1.dmg` from Releases on this page. Open it, drag Media Center into Applications, then open it from Applications.

Testing included copying the DMG on a USB stick to a second Mac, where it opened with no warning. This beta is not notarized, so a warning on some other Macs is still possible. If a warning appears, right-click the app, choose Open, then choose Open again. It only asks once.

## Features

- One library for music and movies, from user-selected folders. Defaults are the Music and Movies folders.
- Audio playback: MP3, M4A, AAC, Apple Lossless, FLAC, WAV, AIFF, CAF, MP2, M4B. Video playback: MP4, M4V, MOV, 3GP.
- Listed but not playable: MKV, AVI, WMV, MPG/MPEG, WebM, FLV, OGG, VOB, and others. Apple ships no decoder for these formats, so the app labels them with the real format, for example "MPG - not playable", instead of hiding the limit.
- Automatic metadata: song info, artwork, and time-synced lyrics from MusicBrainz, iTunes, and LRCLIB. A "Fill in blank songs" button processes missing entries in a batch.
- Karaoke lyrics: the current line is bright, other lines are dim, and the list scrolls up slowly to follow playback.
- Movie captions: a .srt file next to the movie is used when present. Otherwise captions are generated on device from the movie audio.
- Playlists, drag and drop, multi-select, shuffle, resume, and AirPlay / Bluetooth from the player bar.
- Liquid Glass design on macOS 26, with a frosted fallback on older macOS. Minimum macOS 14.

## Technical overview

- Front end: SwiftUI, with AVPlayer for playback and a small audio tap for live levels.
- Library: scanned locally and stored as JSON, with playlists and session state in separate files.
- Metadata: lookups to MusicBrainz, iTunes, and LRCLIB, only to fill in missing details.
- Captions: generated on device with speech recognition, in short chunks, and cached as JSON. No audio leaves the Mac for caption generation.
- Artwork: cached locally and downscaled to the displayed size, to keep scrolling light.
- Tags: written into a song file only on explicit user action, and only for M4A files.

## Data and privacy

- Music and movies stay in place. The app only reads them.
- App data (library list, playlists, downloaded artwork, captions) lives in a dedicated folder: `~/Library/Application Support/MediaCenter/`
- Nothing is uploaded to a server. There is no account and no cloud. Song info is looked up online only to fill in missing details.

## Build from source

A Mac with Xcode is required.

1. Open `MediaCenter.xcodeproj` in Xcode.
2. Press Cmd+B to build, Cmd+R to run.
3. To make a .dmg for sharing, use `create-dmg` (install with Homebrew: `brew install create-dmg`) or the `make-dmg.sh` script in this repo.

## Feedback

Bugs and usability issues can be opened as GitHub Issues. Useful reports include what happened, what was expected, and the macOS version. Screenshots help.

## License

MIT. See `LICENSE`. Free to use and share.

