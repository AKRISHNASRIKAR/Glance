# Glance landing page

A standalone, responsive static website for Glance. No Node packages or build step required; the native Swift app remains independent.

## Preview

From the repository root:

```sh
python3 -m http.server 4173 --directory frontend
```

Open http://localhost:4173. You can also open `index.html` directly.

## Deploy

Publish the `frontend/` directory with any static host. It contains the complete page and its local assets. No environment variables are required. Google Fonts is optional: system font fallbacks are provided when offline.

The notch illustration is a labeled demo. Its controls demonstrate sample playback and a browser-local Pomodoro timer. They do not control the native app. Release and installation links point to the project's GitHub repository.

## Device illustration

The hero uses an original CSS illustration inspired by the 13-inch M4 MacBook Air (2025), with a 13.6-inch display and a camera notch. Reference: [Apple product announcement](https://www.apple.com/newsroom/2025/03/apple-introduces-the-new-macbook-air-with-the-m4-chip-and-a-sky-blue-color/) and [technical specifications](https://support.apple.com/en-ie/122209). The illustration uses no third-party device image or 3D asset.

## Native UI reference

The MacBook notch preview follows the current SwiftUI source: 480-point expanded width, a 32-point illustrated sensor row, 128-point content area, 22-point bottom corners, 82-point album artwork, centered transport controls, and the app’s chevron/dot pager. The selected examples are Now Playing (Artwork), Pomodoro (Classic), and Claude Code (needs-input state). Claude is optional in the app.

`native-preview.css` maps native points to container-relative units. Match future app changes against `NotchGeometry.swift`, `NowPlayingScreenView.swift`, `PomodoroUIKit.swift`, `ClassicPomodoroRenderer.swift`, `ClaudeCodeScreenView.swift`, and `ExpandedContentView.swift`. The browser recreation uses equivalent web glyphs, not Apple SF Symbols; native rendering and browser rendering are not pixel-identical. Media artwork and track details come from the repository screenshot.

## Motion

`motion.css` adds section reveals, preview transitions, button feedback, and a breathing timer halo. The timer arc reflects elapsed demo time; pulsing represents a running state, not progress. Native Classic and Artwork Pomodoro use an 88-point ring and animated rounded numeric text. Site and native animations respect Reduce Motion, and timer breathing stops when paused.

The hosted Pomodoro preview now matches the centered Classic layout, with full-notch sage/plum focus and blue/plum rest gradients. Claude uses a full-notch terracotta/plum background.

## Device illustration

The hero uses a responsive CSS MacBook illustration in `macbook-m4.css`, with a unified bezel, sage wallpaper, and interactive Glance preview. The Apple reference image remains in assets for design reference but is not rendered in the hero.
