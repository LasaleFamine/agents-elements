## Install

1. Download the `AgentsElements-*.zip` asset below and unzip it.
2. Move **AgentsElements.app** to **/Applications**.
3. The app is open-source and **ad-hoc signed (not notarized by Apple)**, so on first launch
   macOS Gatekeeper blocks it with *"Apple could not verify…"*. Open it once with either:

   **Terminal** — removes the download quarantine flag, then opens:
   ```bash
   xattr -dr com.apple.quarantine /Applications/AgentsElements.app
   open /Applications/AgentsElements.app
   ```

   **or the GUI** — double-click (you'll get the block), then go to **System Settings →
   Privacy & Security**, find *"AgentsElements was blocked…"*, and click **Open Anyway**.
   (On macOS 15 Sequoia the old Control-click → Open shortcut no longer works for
   un-notarized apps.)

You only need to do this once. Prefer no warning at all? Build from source — locally built
apps aren't quarantined.

---

