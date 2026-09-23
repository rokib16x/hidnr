cask "hidnr" do
  version "0.1.0"
  sha256 "043c39e2578e225e3b78a02fa58c73f8d2d79748695cd9b6977989ac3994eff3"

  url "https://github.com/rokib16x/hidnr/releases/download/v#{version}/hidnr-#{version}.dmg"
  name "hidnr"
  desc "Hide the menu bar icons you don't need"
  homepage "https://github.com/rokib16x/hidnr"

  depends_on macos: ">= :sonoma"

  app "hidnr.app"

  uninstall quit: "com.rokib16x.hidnr"

  zap trash: "~/Library/Preferences/com.rokib16x.hidnr.plist"
end
