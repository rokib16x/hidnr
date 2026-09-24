cask "hidnr" do
  version "0.1.2"
  sha256 "84125cadb1d8760d075fb751bb661c100b41747fc66dd85172af3181c5c5f284"

  url "https://github.com/rokib16x/hidnr/releases/download/v#{version}/hidnr-#{version}.dmg"
  name "hidnr"
  desc "Hide the menu bar icons you don't need"
  homepage "https://github.com/rokib16x/hidnr"

  depends_on macos: ">= :sonoma"

  app "hidnr.app"

  uninstall quit: "com.rokib16x.hidnr"

  zap trash: "~/Library/Preferences/com.rokib16x.hidnr.plist"
end
