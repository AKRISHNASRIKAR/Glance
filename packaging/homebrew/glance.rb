# Homebrew Cask template for Glance.
#
# NOT auto-published. After a signed + notarized GitHub Release:
#   1. Replace REPO_OWNER with the GitHub owner of this repository.
#   2. Update `version` to the released version.
#   3. Update `sha256` with the value from checksums-<version>.sha256
#      (the DMG line).
#   4. Submit to homebrew-cask or host in your own tap
#      (e.g. github.com/REPO_OWNER/homebrew-tap).
#
# Full steps: docs/RELEASING.md.

cask "glance" do
  version "0.1.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/REPO_OWNER/glance/releases/download/v#{version}/Glance-#{version}.dmg"
  name "Glance"
  desc "Configurable, context-aware Live Activity layer for the MacBook notch"
  homepage "https://github.com/REPO_OWNER/glance"

  depends_on macos: ">= :sonoma"

  app "Glance.app"

  uninstall quit: "app.glance.Glance"

  zap trash: [
    "~/Library/Application Support/Glance",
  ]
end
