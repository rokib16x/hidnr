cask "hidnr" do
  version "0.1.1"
  sha256 "c99486dc41dbb021fb9490573fdc6c90a33e1c8c75c4c9594082a51e3e8a3713"

  url "https://github.com/rokib16x/hidnr/releases/download/v#{version}/hidnr-#{version}.dmg"
  name "hidnr"
  desc "Hide the menu bar icons you don't need"
  homepage "https://github.com/rokib16x/hidnr"

  depends_on macos: ">= :sonoma"

  app "hidnr.app"

  uninstall quit: "com.rokib16x.hidnr"

  zap trash: "~/Library/Preferences/com.rokib16x.hidnr.plist"
end
