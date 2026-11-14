# Swivel for iPhone and iPad (first draft, not yet compiled)

This folder is the app that carries the game. Nothing here has been built yet: there is no Mac in
the workspace it was written in. The first run of the workflow on GitHub is the first real check.

## What is here

| File | What it is |
|---|---|
| `Swivel/AppDelegate.swift` | Starts the app, sets the sound to play over the player's music, makes the one game |
| `Swivel/SceneDelegate.swift` | The game's window, and the links the app is opened with (`swivel://...`) |
| `Swivel/GameViewController.swift` | The web view that shows the game, and the handler for the page's messages |
| `Swivel/Haptics.swift` | The phone's taps, by the names the game uses: tap, wave, blocked, jam, win, switch |
| `Swivel/Keep.swift` | The app's copy of what the page stores, on the device and in the player's iCloud |
| `Swivel/GameCenter.swift` | Passes the game's achievements and scores to Game Center, and opens Apple's Game Center screen |
| `Swivel/Reminder.swift` | The daily reminder: local notifications, two weeks at a time, only if the player asks |
| `Swivel/Review.swift` | Picks a good moment to ask for a rating, and opens the App Store's review page for the Rate button |
| `Swivel/Web/` | The game: `dist/app/` from the web project, copied here by `node tools/build.js` |
| `Swivel/Info.plist` | Name, orientations, launch colour, "no encryption" answer, the `swivel://` link scheme, the one scene, `SwivelAppStoreID` (6834924690) |
| `Swivel/Swivel.entitlements` | iCloud key-value storage, Game Center |
| `Swivel/PrivacyInfo.xcprivacy` | Apple's privacy manifest: no tracking, nothing collected, UserDefaults for the app's own use |
| `Swivel/Assets.xcassets` | The 1024 icon and the launch colour |
| `project.yml` | The recipe XcodeGen turns into `Swivel.xcodeproj` |
| `ExportOptions.plist` | How the signed app is sent to App Store Connect |
| `workflow-ios.yml` | The GitHub Actions workflow (goes in `.github/workflows/ios.yml`) |

## The page and the app talk through one channel

The page posts `{ type, data }` to `window.webkit.messageHandlers.swivel`:

| type | data | the app |
|---|---|---|
| `ready` | `{ version, build }` | shows the web view (it is hidden until then, so nothing flashes) |
| `haptic` | `tap`, `wave`, `blocked`, `jam`, `win` or `switch` | plays that tap |
| `store` | `{ key: text }`, the page's storage | keeps it on the device |
| `progress` | the record, as JSON text | keeps it on the device and in iCloud |
| `copy` | text | puts it on the clipboard |
| `share` | `{ text, url }` | opens the phone's share sheet with both |
| `game` | `{ feats: { name: 0..100 }, scores: { name: number } }` | passes them to Game Center as `swivel.<name>` (only upward) |
| `gamecenter` | none | opens Apple's Game Center screen, or its sign-in if the player is signed out |
| `moment` | `{ kind: world, ending or streak }` | may ask the phone to show its rating question (once a version at most) |
| `rate` | none | opens the App Store's review page (the button only shows when `SwivelAppStoreID` is set) |
| `remind` | a plan `{ on: true, hour, done, streak, days: [{ date, name }] }`, or `{ on: false }` | schedules or clears the reminders, then answers through `__swivelReminder` |

The app gives back, before the page's script runs: `window.__swivelShell = { store, progress, otherAudio, reminder, rate, open }`
(`reminder` is `on`, `off` or `unset`; `rate` is true once `SwivelAppStoreID` is set; `open` is a link the app was started with).
A link that arrives later is passed in with `window.__swivelOpen(link)`, and the reminder's state with
`window.__swivelReminder('on' | 'off' | 'denied')`.
`otherAudio` in that object is true when the player's own music is playing; the game then keeps its
music off. A change is passed in with `window.__swivelOtherAudio(true or false)`.
While the game is open, a change from iCloud is passed in with `window.__swivelProgress(json)`.
The page's side of all this is tested in `tests/e2e2.js` (section 14) and `tests/e2e3.js` (sections 4, 5 and 7),
with a stand-in for the app. The Swift side has never been compiled or run.

## Built for the iOS 27 tools as well as the iOS 26 ones

From the iOS 27 tools (Xcode 27) on, an app that does not take its window as a "scene" does not start, and an
app with no launch screen is turned away by the App Store. Both are in place: `SceneDelegate.swift` with the
`UIApplicationSceneManifest` entry in `Info.plist`, and `UILaunchScreen` (the night-sky colour). The workflow
builds with whatever Xcode is the default on GitHub's `macos-26` machines; when Apple starts asking for
Xcode 27 builds, only the machine or the Xcode chosen in the workflow has to change.

## To do in Apple's own pages before these work

- **Game Center:** tick it on the app's identifier, turn it on for the app in App Store Connect, and add the
  3 leaderboards and 30 achievements in `store/gamecenter.md`. Each achievement needs a picture.
- **Rate button:** put the app's App Store number in `SwivelAppStoreID` in `Info.plist`.
- **An event card on the App Store:** its link is `swivel://daily` (or `swivel://d=2026-12-31` for one day's board).
- **Links to the game's web page opening the app** (and not the browser) need an associated domain, which
  needs a web address whose root we control. Not set up. Until then shared links open in the browser, where the
  board plays, and `swivel://` links open the app.

## Still open

- **The typeface.** `assets/fonts/overpass-500.woff2`, `-700` and `-900` are not in the project yet.
  Until they are, the app uses the phone's own sans-serif.
- **Identifier and team.** `BUNDLE_ID` and `TEAM_ID` come from the Apple Developer account.
- **Status bar.** Hidden for now (`prefersStatusBarHidden` in `GameViewController.swift`).
- **Never run on a device:** haptics, sound with the silent switch, iCloud, the iPad layout, Game Center,
  the share sheet (on an iPad it is a popover and is given the middle of the screen to come from), the
  reminder's permission question and its notices, the rating question (it never shows in TestFlight), and links.
