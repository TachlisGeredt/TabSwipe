# TabSwipe

I have an unhealthy habit of accumulating vast quantities of tabs in my browser window, to the point where it is hard to tell which tab is which as the title is not visible, or it's annoying to click on that tiny spot which is the tab I want to open.

To this end, I made a macOS utility that lets you use the 3-finger swipe to move between tabs when in a browser. All you need to do is hold down the **⌘ Command** button (right by your thumb), and then your 3-finger swipes will move you a tab to the left or to the right instead of switching desktops.

## Features

- **Zero UI, zero config files, zero dependencies** — pure native Swift LaunchAgent daemon (~3–6 MB RAM, ~0.0% idle CPU).
- **Browser-only activation** — listens for active-app changes via `NSWorkspace` (zero polling) and **disables its event tap completely** whenever a non-browser app is focused.
- **Intuitive single-step gesture**:
  - Hold **⌘** (Left or Right, no other modifiers) + **3-finger swipe left** → move 1 tab right (next tab, matching macOS Spaces natural direction).
  - Hold **⌘** + **3-finger swipe right** → move 1 tab left (previous tab).
  - Keep holding **⌘**, lift your fingers, and swipe again to keep stepping through tabs.
  - Release **⌘** → normal macOS 3-finger Space switching works untouched.

## Supported Browsers

Built-in support (see `Sources/TabSwipeCore/BrowserRegistry.swift`):

- Safari (& Safari Technology Preview)
- Google Chrome (Stable, Beta, Dev, Canary)
- Brave (Stable, Beta, Nightly)
- Firefox (Stable, Developer Edition, Nightly)
- Microsoft Edge (Stable, Beta, Dev, Canary)
- Arc
- Vivaldi
- Opera (& Opera GX)
- Orion
- Zen Browser
- Chromium

## Requirements

- macOS 13 (Ventura) or later
- Apple Command Line Tools (`xcode-select --install`) to build from source (no Xcode IDE required)

## Build & Install

```bash
git clone https://github.com/<your-username>/TabSwipe.git
cd TabSwipe
make install
```

Or build and run tests manually (works with Apple Command Line Tools alone, no Xcode required; compiles into `$TMPDIR/tabswipe-build` so your source directory stays clean):

```bash
make build
make test
make install
```

*(If you have full Xcode installed, `swift build -c release` and `swift test` also work.)*

`tabswipe install` copies the binary to `~/.local/bin/tabswipe`, registers a LaunchAgent at `~/Library/LaunchAgents/com.tabswipe.agent.plist`, starts it, and opens **System Settings → Privacy & Security → Accessibility**.

### Grant Accessibility Permission

1. `make install` automatically registers `tabswipe` with macOS and opens **System Settings → Privacy & Security → Accessibility**.
2. Enable the toggle next to **tabswipe** *(if you reinstalled over an older ad-hoc build, remove `tabswipe` with **−** and re-add `~/.local/bin/tabswipe` with **+**)*.
3. TabSwipe checks quietly every 5 seconds and activates automatically once granted. *(If `tabswipe` doesn't appear automatically, click **+** and add `~/.local/bin/tabswipe`.)*

#### Optional: Keep Accessibility Permission Across Rebuilds
If you modify and rebuild TabSwipe often, create a free local self-signed certificate once in **Keychain Access**:
1. Open **Keychain Access** → menu bar **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Set **Name** to `TabSwipe`, **Identity Type** to `Self Signed Root`, and **Certificate Type** to `Code Signing`, then click **Create**.
3. `make install` automatically detects the `TabSwipe` certificate (or `TABSWIPE_CODESIGN_IDENTITY`) and signs with it so macOS preserves Accessibility permission on every future rebuild.

## Commands

```bash
~/.local/bin/tabswipe status     # Check LaunchAgent status and recent logs
~/.local/bin/tabswipe uninstall  # Stop and remove the LaunchAgent and binary
~/.local/bin/tabswipe run        # Run in foreground (for debugging)
```

## Customizing

Want to add a browser or tweak swipe sensitivity?

- **Add a browser**: Add its macOS bundle ID to `Sources/TabSwipeCore/BrowserRegistry.swift`.
- **Adjust swipe sensitivity**: Change `horizontalThreshold` (default `0.035`) in `Sources/TabSwipeCore/SwipeRecognizer.swift`.
- Rebuild and reinstall:

```bash
make install
```

## Built With

- **Harness**: Google Antigravity (using `/plan` and `/grill-me` workflows)
- **Model & Settings**: Gemini 4 Neon (Medium)

## License

MIT — see [LICENSE](LICENSE).
