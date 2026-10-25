# Launch Window v1.0.0

iOS app + widgets + Live Activity that counts down to the next (or followed) rocket launch.

## What v1.0.0 actually is — and is not

In scope: upcoming launches worldwide from Launch Library 2, mission detail, pad/location, live-stream link, Follow to pin, Small/Medium home widgets, Circular/Rectangular/Inline lock-screen widgets, and a manual Live Activity.

Out of scope for v1.0.0 (do not promise them yet): automatic final-hour Live Activity start, local notifications at T-1h/T-10m, App Intents widget configuration, a Mars/L2 tab, and a shareable launch card. Those are listed at the bottom as later steps, with the reason each one is not free.

## Order matters — do it in this order

### 1. Deploy the Worker first

```
cd worker
npx wrangler deploy
curl https://launchwindow.<you>.workers.dev/launches | head -c 300
```

No cron triggers in `wrangler.toml`, on purpose: the free-plan trigger quota fails deploys. The Worker is lazy-refresh only (5-minute cache, stale copy served if LL2 is down).

### 2. Paste the Worker URL into the app, then build

In `Shared/LaunchAPI.swift`, set:

```swift
static let workerBaseURL = "https://launchwindow.<you>.workers.dev"
```

If you build with it empty, the app *and* the widget each call Launch Library 2 directly, and together they can burn the unauthenticated limit — 15 requests per hour — before the widget ever refreshes.

### 3. Apple side (once)

- App IDs: `studio.mikegyver.launchwindow` and `studio.mikegyver.launchwindow.widget`
- App Group `group.studio.mikegyver.launchwindow` enabled on **both** App IDs and in both targets' entitlements. One side only fails silently: the widget then shows the next launch, not your pinned one.
- Repository secrets (same four as PodMix / Cosmic Jukebox): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `TEAM_ID`

### 4. Push and tag

On Windows, from the unzipped folder:

```
.\push-launchwindow.ps1
```

That script creates `MikeGyver-SME/mikegyver-launchwindow` if needed, pushes, and tags `v1.0.0`. The tag triggers the GitHub Actions workflow, which builds with fastlane signing (app + widget profiles) and uploads to TestFlight. Bump `CURRENT_PROJECT_VERSION` in `project.yml` before any re-upload of the same version — TestFlight rejects a duplicate version/build pair.

Local build (needs a Mac with Xcode):

```
brew install xcodegen
xcodegen generate && open LaunchWindow.xcodeproj
```

## Corrections to the original brief

- **Bundles:** `com.mikegyver.*` changed to `studio.mikegyver.*`, matching PodMix, WalkLog, and Cosmic Jukebox. The App Group changed with it.
- **Project file:** the starter relied on XcodeGen to generate Info.plists and entitlements from `project.yml`. This version ships hand-written plists and entitlements, like Cosmic Jukebox, and the workflow guards them against XcodeGen overwrite. It also adds the missing `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` and `embed: true` for the widget.
- **App Group sync:** the starter wrote to the group defaults but never called `CFPreferencesAppSynchronize`, and it silently fell back to `.standard` when the group was unreachable. Writes now synchronize, cache writes now reload widget timelines (the starter only reloaded on pin changes), and the group-reachable check is explicit.
- **Countdown:** the starter showed `T-0m` for a full minute before liftoff. Under one minute it now shows seconds.
- **NET is not a promise:** NET means "no earlier than". A launch with `net_precision` of Month or Quarter is not a minute-accurate countdown, so the detail view now shows the precision, and the status abbreviations are Go / TBC (to be confirmed) / TBD (to be determined).
- **Widget refresh:** the starter's "refresh every 15–30 minutes, tighter near T-0" reads as live ticking. WidgetKit timelines are precomputed snapshots under a system budget — the 15-min / 5-min / 1-min steps are requests, not guarantees. The widget text is computed from each entry's date, so it steps forward as entries pass; only the Live Activity's `.timer` text actually ticks every second.
- **Lock-screen wording:** the brief said the lock-screen version shows "just T-2d 4h". The Inline widget in code shows countdown *plus* mission name, because a bare countdown with no mission is meaningless on a lock screen. Circular strips the `T-` prefix for space; Rectangular adds the pad.
- **Small widget:** the brief said Small shows only a countdown. The code — kept — shows mission name + countdown + status, because otherwise you cannot tell which launch you pinned.
- **Live Activity:** the brief said it "counts down during the final hour". A Live Activity lives at most ~8 hours, and this build has no push-to-start, so starting one when you Follow a launch days out would kill it before liftoff. Follow now pins the widget; the Live button appears only inside the final 8 hours, and Follow starts a Live Activity only inside that window. Tap Live in the final hour for the real thing.
- **Live-stream link:** LL2's first `vidURLs` entry is used. That is not always the official provider stream, and sometimes it is empty — the Watch button simply does not appear in that case. Do not promise "official stream for every launch".

## Structure

- `Shared/` — model, API client, App Group store, T-minus formatting (compiled into both targets)
- `LaunchWindow/` — SwiftUI app: list, detail, follow, Live Activity start
- `LaunchWidget/` — home/lock-screen widgets (small, medium, circular, rectangular, inline) + Live Activity UI. Has a `@main` WidgetBundle — required, or Apple rejects the upload with altool error 90896.
- `worker/` — Cloudflare Worker caching Launch Library 2
- `.github/workflows/testflight.yml` — tag-triggered TestFlight build (fastlane signing, app + widget profiles)

## Data and credit

Launch data: Launch Library 2 by TheSpaceDevs (`ll.thespacedevs.com/2.2.0`), free, 15 unauthenticated requests per hour. All data goes through the Worker in this build; the app never needs an LL2 API key.

## Later steps (not in v1.0.0)

- Push-to-start Live Activities via APNs from the Worker near T-0 — this is the only way to get a true automatic final-hour start, and it needs an APNs key, a device token store, and a launch-watch trigger. It is not a small add-on.
- Local notifications at T-1h and T-10m for the followed launch.
- App Intents widget configuration (choose provider/pad).
- Shareable launch card.
- Mars/L2 mission tracker tab using JPL Horizons light-time data — a separate data source and a separate tab, not a weekend add-on to a launch countdown. Ship the countdown first, then decide if that tab earns its own release.
