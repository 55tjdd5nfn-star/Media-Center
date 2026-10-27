cask "media-center" do
  version "1.1"
  sha256 "PUT_THE_SHA256_HERE"
  url "https://github.com/USERNAME/Media-Center/releases/download/v1.1-beta/MediaCenter-1.1.dmg"
  name "Media Center"
  desc "Free music and movie library for macOS"
  homepage "https://github.com/USERNAME/Media-Center"

  app "Media Center.app"

  zap trash: [
    "~/Library/Application Support/MediaCenter",
    "~/Library/Preferences/com.frank.mediacenter.plist",
  ]
end
