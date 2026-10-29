# Rampa

An intentionally empty iOS app whose only real subject is its navigation bar.

Five destinations live inside a single translucent Liquid Glass lozenge that
floats above the home indicator. A tinted lens travels between them — tap a
destination, or drag horizontally on the bar and flick. The content behind is a
soft pool of accent light that drifts as you move, because a glass surface over
flat colour reads as a grey pill.

Built with SwiftUI for iOS 27, running on `xcode-27` GitHub runners, shipped as
an unsigned `.ipa` with a SideStore source.

## The bar

| | |
|---|---|
| Material | `glassEffect(_:in:)` — `.regular`, tinted `#2F5BEA` at 6% |
| Shape | `Capsule` — one continuous surface, 60 pt tall |
| Lens | Tinted capsule, 26% → 12% vertical gradient, hairline rim at 22% white |
| Slide | `Animation.smooth(duration: 0.34, extraBounce: 0.06)` |
| Stage | `Animation.smooth(duration: 0.38, extraBounce: 0.04)` + 14 pt glide |
| Ambient | `Animation.smooth(duration: 0.65)` |
| Feedback | `sensoryFeedback(.selection, trigger:)` |

The lens is *not* glass. Glass cannot sample other glass, so a second glass
surface inside the bar muddies the material — it is a tinted capsule with a rim
instead, which is also what the system does for its own segmented glass.

Everything degrades: `accessibilityReduceMotion` swaps every spring for a 0.16 s
ease and drops the lens drag, `accessibilityReduceTransparency` removes the tint,
and anything below iOS 26 falls back to `.ultraThinMaterial`.

## Install

The `.ipa` is unsigned. Use a signer:

- **SideStore / AltStore** — add the source
  `https://leboxis.github.io/rampa/repo.json`, or sideload
  [the latest `.ipa`](https://github.com/Leboxis/rampa/releases/latest/download/Rampa.ipa) directly.
- **LiveContainer** — import the `.ipa` from the Files app.
- **TrollStore** — open the `.ipa` on a supported firmware.

The source manifest lives at [`docs/repo.json`](docs/repo.json) and is served by
GitHub Pages. `size` and `date` in it are informational; the download URL is
stable (`releases/latest/download/Rampa.ipa`), so it never needs editing again.

## Build

Locally, on a Mac:

```sh
xcodebuild -project Rampa.xcodeproj -scheme Rampa -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/Rampa.xcarchive archive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

In CI, [`.github/workflows/build.yml`](.github/workflows/build.yml) runs on every
push and pull request, uploads the `.ipa` as an artifact, and — on a `v*` tag —
publishes it as a GitHub Release. To cut a release:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

## Layout

```
Rampa/
  App/            RampaApp, RootView
  Navigation/     AppTab, GlassTabBar
  DesignSystem/   Theme, GlassSurface, PressScaleStyle, AmbientBackdrop
  Features/       TabStageView
  Resources/      Assets.xcassets
Support/          Info.plist
docs/             repo.json + source art
```

## Licence

MIT.
