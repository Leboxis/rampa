# Rampa

An iOS app for actually emptying your camera roll, wrapped around a navigation
bar worth looking at.

Five destinations live inside a single translucent Liquid Glass lozenge that
floats above the home indicator. A tinted lens travels between them — tap a
destination, or drag horizontally on the bar and flick. Each one does a real job.

| Tab | What it does |
|---|---|
| **Photos** | The whole library, grouped by month, year, size or type, with pinned headers |
| **Revue** | Swipe triage: left stages to the bin, right keeps |
| **Trier** | Cleanup proposals — old screenshots, heavy videos, bursts, tiny images |
| **Chercher** | Search over date, month, year, kind, size, screenshots, favourites |
| **Panier** | The bin, and the only place anything is ever deleted |

## Looking, then acting

A tap on a photo used to stage it for deletion — a startling thing for a tap on
a picture to do, and it made the library useless for actually *looking* at your
photos. The gestures now follow the grammar every photo app already taught you:

| Gesture | Result |
|---|---|
| Tap | Opens the viewer: the whole photo, uncropped, with its actions underneath |
| Long press | A context menu — favourite, bin, select |
| Tap in selection mode | Ticks the photo |

The viewer is the point. It shows the asset at its true aspect ratio (the deck
used to crop every portrait shot to a square), plays videos in place, and states
the facts PhotoKit is willing to share — date, dimensions, weight, duration —
with a line saying plainly that Apple does not hand over content or place.

## Multi-select

Ticking anything puts the screen in selection mode, and the navigation bar is
replaced — not covered — by a selection bar: a select-all control, a live count,
the actions that screen supports, and Terminé. Selection is tracked **per tab**,
so leaving a screen abandons its ticks instead of leaving a bar counting photos
you can no longer see.

The bar only ever offers what is true of that screen. Library, search and
cleanup get *favourite* and *mettre au panier*; the bin gets *retirer du panier*
and nothing else, because staging what is already staged would be a loop.

## Undo

Staging, un-staging and emptying the bin all offer an undo in a banner above the
bar. "Vider" used to be a one-way door. Undo restores the exact previous order,
so a multi-item undo does not reverse the bin.

## The four rails

Deleting a photo is irreversible in almost every app. Here it takes four
deliberate steps, and the fourth is not even in this app:

1. **Staging.** Nothing is deleted from a tap. An asset enters the bin, where it
   sits until you say otherwise. Undo is a tap on the item.
2. **Hold to confirm.** The delete button is not a button, it is a 1.4 s hold
   with a ring closing over it. Release early and nothing happens — no dialog,
   no penalty, no state change.
3. **Plain language.** A sheet states the count and exactly what will happen,
   before anything is asked of the user's face.
4. **Biometrics.** `LAContext` with `deviceOwnerAuthentication` — Face ID, Touch
   ID, or the passcode. If the device has neither configured, the app **refuses
   to delete** rather than silently downgrading the guard.

Only then does PhotoKit run `deleteAssets`, which moves the assets to the
system's *Recently Deleted* album. Apple keeps them there for 30 days. The app
never calls a permanent-delete API, because PhotoKit does not expose one — and
that is the last rail: the final authority is iOS itself.

## Motion

| | |
|---|---|
| Material | `glassEffect(_:in:)` — `.regular`, tinted `#2F5BEA` at 6% |
| Shape | `Capsule` — one continuous surface, 60 pt tall |
| Lens | Tinted capsule, 26% → 12% vertical gradient, hairline rim at 22% white |
| Slide | `Animation.smooth(duration: 0.34, extraBounce: 0.06)` |
| Ambient | `Animation.smooth(duration: 0.65)` — slower, so the background lags |
| Feedback | `sensoryFeedback(.selection, trigger:)` |
| Targets | 44 pt minimum per destination, labels always visible |

The lens, the stage cross-fade and the ambient pool all run on `Motion.pill`.
Sharing one curve is what makes the bar and the content look like two views of
the same state change rather than two animations that happen to start together.

The lens is *not* glass. Glass cannot sample other glass, so a second glass
surface inside the bar muddies the material — it is a tinted capsule with a rim
instead, which is also what the system does for its own segmented glass.

## Performance

The grid is the part that has to hold 120 Hz, so:

- Thumbnails are downsampled to their exact drawn size. A 48 MP decode is over
  200 MB; a 160 pt cell is a few KB of pixels.
- The PhotoKit request runs in a `nonisolated` helper, so no decode touches the
  main actor and no `PHAsset` crosses an actor boundary.
- `NSCache` is budgeted in real bitmap bytes — the cost was previously
  multiplied by the *view's* scale, which over-charged every entry by up to 9×
  and evicted the cache constantly.
- Grouping, sorting and search run in `Task.detached`, keyed on their inputs,
  never inside a view body.
- The library fetch itself is `nonisolated`: enumerating 20 000 assets on the
  main actor at launch was a visible hitch.
- Each grid keeps an id→index map built once per list. The prefetcher used to
  call `firstIndex(where:)` per cell that appeared, which is O(n²) per screen.
- The next 24 thumbnails are prefetched as you scroll, through one long-lived
  `PHCachingImageManager` — the old one was created and dropped per call, so it
  never actually cached anything.

## Search, honestly

PhotoKit gives third-party apps no content, caption or place metadata. So the
search covers what the app legitimately has — date, month, year, kind, size
bucket, screenshots, favourites — and the screen says so instead of letting
someone type "plage" and get a silent empty grid.

## Install

The `.ipa` is unsigned. Use a signer:

- **SideStore / AltStore** — add the source
  `https://leboxis.github.io/rampa/repo.json`, or sideload
  [the latest `.ipa`](https://github.com/Leboxis/rampa/releases/latest/download/Rampa.ipa) directly.
- **LiveContainer** — import the `.ipa` from the Files app.
- **TrollStore** — open the `.ipa` on a supported firmware.

The source manifest lives at [`docs/repo.json`](docs/repo.json) and is served by
GitHub Pages at <https://leboxis.github.io/rampa/>. Its download URL points at
`releases/latest/download/Rampa.ipa`, which always resolves to the newest
release, so the manifest never needs editing when a build ships.

> **Note on permissions.** Rampa asks for full photo library access — a sorting
> app that can only see three photos cannot sort anything. Nothing leaves the
> device: there is no network code in this app at all.

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
publishes it as a GitHub Release. The release step is idempotent, so re-running
on a moved tag replaces the asset instead of failing. To cut a release:

```sh
git tag v2.0.0 && git push origin v2.0.0
```

The project uses file-system-synchronized groups, so adding a Swift file under
`Rampa/` needs no `project.pbxproj` edit.

## Layout

```
Rampa/
  App/            RampaApp, RootView, AppState
  Navigation/     AppTab, GlassTabBar
  DesignSystem/   Theme, GlassSurface, PressScaleStyle, AmbientBackdrop,
                  HoldToConfirmButton, ScreenChrome, SelectionBar
  Media/          MediaItem, MediaTypes, MediaLibrary, MediaActions,
                  ThumbnailLoader, ThumbnailView, MediaCell, MediaGrid,
                  MediaViewer, MediaAnalyzer, DeletionGuard
  Features/       LibraryScreen, ReviewScreen, CleanupScreen,
                  SearchScreen, BinScreen
  Resources/      Assets.xcassets
Support/          Info.plist
docs/             repo.json, index.html, source art
```

## Licence

MIT.
