# iPhone tagging app: plan

Status: plan only, nothing built. Facts marked "checked" were verified against primary sources on 21 November 2026;
nothing here has been tested on a device. This repository is public, so this document uses two roles and no personal
details: the **tagger** (iPhone, Mac, iCloud) and the **maintainer** (Android, Windows, OneDrive).

## 1. What the app does

The tagger opens the app, sees a short queue of photos, and taps the ones worth sharing. The app learns from those
decisions. Over time it stops asking about photos it is sure of and only shows the uncertain ones. Photos marked for
sharing are uploaded as originals to a OneDrive folder the maintainer owns.

Everything except the upload happens on the phone. No photo, embedding, label or trained weight leaves the device
other than the originals the tagger approved.

## 2. What the checks changed

| Finding (checked) | Consequence for the design |
| --- | --- |
| iPhone apps cannot read named People, Apple's scene labels, or the "saved from app" attribution. | The phone has weaker signals than a Mac script. "Saved from a messenger" must be inferred from file type, filename, size and missing location. Expect a larger review pile than the earlier Mac-based estimate. |
| Apps can read screenshot and screen-recording flags, capture date, added date (iOS 26), location, favourite, hidden, burst, source type, and (iOS 27) original filename, caption and keywords. | Screenshots are excluded by rule. The rest become classifier features. |
| Apple publishes MobileCLIP (v1) image encoders as Core ML: S0 23 MB, S1 43 MB, S2 71 MB; 256 px input, 512-dim output; a few milliseconds per image. The licence is research and non-commercial. | Use it for personal use, download it on first run with a pinned revision and checksum, and never commit the model to this repository. Apple's built-in Vision feature print is the zero-download fallback. |
| A free Apple Account can sign apps that use background tasks, Keychain, PhotoKit and local notifications. Signing lasts 7 days; 3 apps per device, and SideStore counts as one. | The app is buildable for free. Keeping it alive is the open risk (section 7). |
| SideStore rewrites the bundle ID to `<bundle id>.<team id>` but keeps app data across refreshes and updates. | Avoid anything tied to the bundle ID, in particular Microsoft's MSAL sign-in library. |
| SideStore on iOS 27 is currently unstable: sign-in has returned HTTP 503 since 20 November 2026, and refresh fails while the phone is locked on iOS 27.2 (open issues, no maintainer reply). | Prove sideloading with a hello-world app before writing the real one. Keep fallbacks ready. |
| GitHub's hosted macOS runners are free for public repositories, and the `xcode-27` image has the iOS 27 SDK. | The app can be compiled without owning a Mac. Build artefacts on a public repository are effectively public, so the build must contain no private values. |
| Registering a Microsoft sign-in app now requires a directory. The free route is an Azure free account (phone and card for identity verification). | One-time setup cost for the maintainer. The share-sheet fallback in section 6 needs no registration. |
| Microsoft supports device-code sign-in for personal accounts, and a `Files.ReadWrite.AppFolder` scope that limits an app to one folder. | Sign-in needs no redirect URI, so bundle-ID rewriting does not matter. The token on the phone can reach one folder only. |
| OneDrive upload sessions return a pre-authenticated URL, accept fragments under 60 MiB, and let the client set created and modified timestamps. | A typical photo uploads as one background request with the capture date preserved. |
| PhotoKit's background upload extension requires a server that speaks the IETF resumable-upload protocol, and has an open bug with iCloud Photos. | Not usable with OneDrive. Use ordinary background tasks and background URL sessions. |

## 3. Components

```
iPhone app
  Library scanner      PhotoKit change history -> new assets since last run
  Rule filter          drops screenshots, screen recordings, hidden, shared-album items
  Embedder             Core ML MobileCLIP-S2 (or Vision feature print) -> 512 floats per photo
  Feature builder      metadata + event context -> ~20 numbers per photo
  Classifier           logistic regression, retrained on device after each session
  Band policy          auto-skip / review / auto-share, thresholds from cross-validation
  Review UI            day-grouped grid, tap to keep, "all" and "none" per day
  Outbox               24-hour holding period, then export original and upload
  Uploader             Microsoft Graph upload sessions via background URLSession
  Store                SQLite: assets, embeddings, labels, scores, upload ledger
OneDrive (maintainer's account)
  Apps/<app name>/YYYY/YYYY-MM/<files>
```

A core Swift package holds everything that does not touch Apple frameworks (classifier, features, thresholds, file
naming, upload state machine). It is written in plain Swift so it can be unit-tested in CI and, where the Swift
toolchain allows, on Windows.

## 4. How it works for the tagger

**One-time setup (done by the maintainer on the tagger's phone)**
1. Install SideStore and the app (section 7).
2. Open the app, grant full photo access and notifications.
3. Connect OneDrive: the app shows a short code, and the maintainer approves it in a browser on their own laptop
   with their own Microsoft account. The app receives a token limited to its own folder.
4. Tap "Index library". The app embeds every photo, newest first. The app is usable as soon as the most recent
   months are done.

**First sessions (before the classifier is trusted)**
1. The app shows recent days, each as a grid, with screenshots already removed.
2. The tagger taps the photos to share, or "share all" or "none" for the whole day, then "done".
3. Photos shown and not picked on a completed day count as "skip". Untouched days count as nothing.
4. Day-level buttons mean a trip of 200 photos is a few taps, so a few hundred labels takes minutes, not an evening.

**Steady state**
1. A notification says, for example, "12 photos to review".
2. The app shows only the uncertain photos, grouped by day, most uncertain first.
3. Confident-share photos sit in the Outbox for 24 hours with a "remove" button, then upload.
4. Confident-skip photos are not shown. A "skipped" tab lets the tagger rescue one, which becomes a strong label.

**After upload**
- A "Shared" tab lists what went out. "Unshare" deletes the file from the OneDrive folder.
- Each shared photo is also added to an ordinary Photos album, as a visible record that survives if the app lapses.

## 5. Classifier

**Hard rules (no model)**
- Never propose: screenshots, screen recordings, hidden items, items that come from a shared album, items already
  uploaded.

**Features**
- The 512-dim image embedding, normalised.
- Capture signals: file type (HEIC, JPEG, PNG), original filename pattern (iOS 27), pixel size matching a camera
  sensor, Live Photo, edited, favourite, has location. These stand in for "taken by this phone" versus "received".
- Place: distance from home. Home is estimated on the device as the densest cluster of photo locations and is never
  stored anywhere else.
- Trip: length of the current run of days away from home.
- Event context: number of photos within two hours, and the share of neighbours in the same event already kept.
- Time: hour and weekday.

**Model and training**
- L2-regularised logistic regression on the concatenated features, class-weighted.
- Retrained from scratch on the phone after each review session. With 20,000 labelled photos this is about 40 MB of
  floats and should take seconds; to be measured in Phase 0.
- Near-duplicates and bursts are collapsed to one representative before review, using embedding similarity and
  timestamps, so the tagger does not answer the same question five times.

**Bands and thresholds**
- Thresholds are set from cross-validated scores, grouped by day so near-duplicates never sit on both sides of a
  split.
- Auto-skip threshold: the score below which at most 2% of the tagger's keeps fall.
- Auto-share threshold: the score above which measured precision is at least 99%. This band stays off until there
  are at least 300 labels including 50 keeps and the target is met.
- Both targets are settings. A wrongly shared photo is the expensive error, so the defaults lean toward asking.

**Where the starting labels come from**
- Day-level tagging in the first sessions.
- Optionally, the tagger picks existing albums of past trips; their contents count as keeps.
- Optionally (later), match the existing shared OneDrive album back to the library by capture time.

**How we will know whether it works**
- A statistics screen shows label counts, cross-validated precision and recall, and the size of each band.
- The classifier first runs in shadow mode: it scores, the tagger still reviews everything, and the app records what
  it would have done. Automation is only switched on if those numbers are acceptable to the tagger.
- No accuracy figure exists for this task. The earlier estimate of 5 to 15% needing review assumed Mac-only signals
  and should be treated as optimistic for the phone.

## 6. Upload to OneDrive

**Registration (maintainer, once)**
- Create an Azure free account, register an app for "Personal accounts only" on the "Mobile and desktop
  applications" platform, enable "Allow public client flows", request `Files.ReadWrite.AppFolder` and
  `offline_access`.
- The client ID is typed or scanned into the app at setup and stored in the Keychain. It is not in the repository or
  the build.

**Sign-in**
- Device-code flow against the `consumers` endpoint. No redirect URI, no MSAL.
- The refresh token lives in the phone's Keychain. Default lifetime is 90 days and it renews on use, so an app left
  unused for three months needs the code step again.

**Destination**
- `Apps/<app name>/YYYY/YYYY-MM/` in the maintainer's OneDrive. The maintainer then shares or moves that folder into
  the joint album. Microsoft's documentation says the app folder may be renamed or moved.

**Export and naming**
- Originals are written to a temporary file with `PHAssetResourceManager`, downloading from iCloud when the phone
  only holds an optimised copy.
- Edited photos upload as the edited version. Live Photos upload as the still only. Videos are off by default and
  Wi-Fi only when on.
- File name: `yyyyMMdd_HHmmss_<8 hex characters>.<ext>`, derived from capture time and the asset identifier. The
  same photo always produces the same name.

**Transfer**
- `createUploadSession` with `conflictBehavior=fail` and `fileSystemInfo` set to the capture date.
- Files under 60 MiB go as a single request on a background URL session. Larger files are sent in sequential
  fragments while the app is open.
- A 409 "name already exists" response is treated as already uploaded. A local ledger records every upload.
- `Retry-After` is honoured; at most two transfers run at once.

**Fallbacks**
- If the app-folder scope turns out not to cover upload sessions, the tagger signs in with a free Microsoft account
  of their own and the app uploads into a folder the maintainer shared with edit rights.
- If registration is not wanted at all, the app exports the approved batch through the iOS share sheet to the
  OneDrive app. That is three taps per batch and needs no Microsoft setup.

## 7. Build, install and the 7-day limit

**Build**
- The Xcode project is generated from a text file (XcodeGen), so it can be authored on Windows.
- A GitHub Actions workflow on the `xcode-27` runner builds, runs unit tests, archives without signing, attaches
  entitlements with `ldid`, and zips an `.ipa`.
- UI tests run in the Simulator with synthetic images and save screenshots, which gives a way to see the app
  without a Mac.
- The compile loop is a push and a wait of several minutes. There is no local build on Windows.

**Install**
- iloader on the maintainer's Windows laptop installs SideStore over USB. The phone needs Developer Mode on and the
  LocalDevVPN helper.
- SideStore signs with a free Apple Account. That account does not have to be the one the phone uses for iCloud. A
  dedicated account keeps the tagger's credentials out of a third-party tool, but one open issue reports refresh
  trouble with a secondary account on iOS 27.0.1.
- Updates install from a link to the latest build.

**Staying alive**
1. SideStore background refresh, plus a daily Shortcuts automation that runs its "Refresh All Apps" action at a time
   the phone is normally unlocked and on Wi-Fi.
2. The app reads its own signing expiry and shows a banner and a notification when two days remain.
3. If SideStore proves unreliable: Sideloadly's Wi-Fi auto-refresh from a computer on the same network.
4. If that fails: a weekly Run from Xcode on the tagger's Mac.
5. Last resort: the paid developer programme.

When signing lapses the app will not open, but its data, labels and classifier are kept.

## 8. Privacy rules for this public repository

**Never committed**
- Names, email addresses, Apple Account or Microsoft account identifiers, Apple team ID, device identifiers.
- Azure tenant and client IDs, OneDrive share links, drive or folder IDs.
- Pairing files, certificates, provisioning profiles.
- Photos, thumbnails, screenshots showing real photos, embeddings, labels, trained weights, home coordinates,
  device logs.
- Model files.

**How that is enforced**
- All account-specific values are entered in the app at runtime and kept in the Keychain. The build contains none,
  so CI needs no secrets and a public `.ipa` reveals nothing.
- `.gitignore` covers local config, signing material, data folders, databases, models and build outputs.
- Tests use synthetic vectors and generated images only.
- GitHub secret scanning and push protection are enabled, with a local `gitleaks` pre-commit check.
- Commits use a GitHub no-reply email address.
- The app has no analytics. It contacts Microsoft for sign-in and upload, and Hugging Face once for the model.
- The diagnostics export contains counts and scores only, never images or locations.

## 9. Phases

| Phase | Work | Done when |
| --- | --- | --- |
| 0a | Hello-world app through CI, installed with SideStore | It survives two 7-day refreshes without a computer, or a fallback is chosen |
| 0b | Azure registration, device-code sign-in and uploads from a script on Windows | A photo and a large video land in the app folder with the right dates; scope and folder-move questions answered |
| 0c | On-phone timing test | Milliseconds per photo, memory use, and thumbnail availability under "Optimise iPhone Storage" are measured |
| 1 | Index, rule filter, review UI, labels, album mirror | The tagger can tag a month of photos in a few minutes |
| 2 | OneDrive connection, Outbox, uploader, Shared tab | Approved photos appear in OneDrive with correct dates and no duplicates |
| 3 | Classifier in shadow mode, statistics screen | Cross-validated numbers exist for the tagger's real photos |
| 4 | Bands switched on: auto-skip first, then auto-share with the holding period | The tagger accepts the measured error rate |
| 5 | Background tasks, notifications, expiry warnings, polish | A week passes with no manual maintenance |

Phase 0 decides whether the rest is worth building. Phase 0b needs no phone and can start immediately.

## 10. Open questions and risks

- **Sideloading on iOS 27.** The largest risk. Current SideStore problems may be temporary; Phase 0a answers it.
- **Phone-only signals.** Without People or "saved from", the classifier may need more review than hoped. Shadow
  mode measures this before any automation.
- **App-folder scope.** Whether it alone allows upload sessions, and whether the folder still works after being
  shared or moved, is not documented. Phase 0b answers it.
- **Pre-authenticated upload URLs.** Microsoft retires them for SharePoint and OneDrive from 1 April 2027; it is
  unclear whether personal OneDrive is included. The uploader keeps a foreground path that sends a token.
- **Thumbnails under optimised storage.** No Apple source guarantees a local 256 px image for every photo. Indexing
  may need Wi-Fi.
- **Background time.** iOS gives little to rarely opened apps. Expect "works when opened, sometimes overnight".
- **OneDrive presentation.** Whether third-party HEIC uploads sort by capture date in the Photos timeline is
  unconfirmed.
- **Model licence.** Research and non-commercial; fine for personal use, not for redistribution in this repository.

## 11. Decisions for the maintainer

1. Which Apple Account signs the app: a dedicated one (recommended) or an existing one.
2. Whether to create the Azure free account, or start with the share-sheet export.
3. Whose Microsoft account is connected on the phone: the maintainer's, limited to the app folder (recommended), or
   a new one for the tagger.
4. Holding period and how cautious auto-share should be.
5. Whether videos are in scope.

## Sources checked

- Apple: [membership comparison](https://developer.apple.com/support/compare-memberships/),
  [supported capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios/),
  [PHAsset](https://developer.apple.com/documentation/photos/phasset),
  [background asset upload](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background),
  [MobileCLIP](https://github.com/apple/ml-mobileclip),
  [Core ML models](https://huggingface.co/apple/coreml-mobileclip)
- SideStore: [docs](https://docs.sidestore.io/docs/installation/install),
  [FAQ](https://docs.sidestore.io/docs/faq),
  [releases](https://github.com/SideStore/SideStore/releases),
  [issue 1745](https://github.com/SideStore/SideStore/issues/1745),
  [issue 1723](https://github.com/SideStore/SideStore/issues/1723)
- GitHub: [hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- Microsoft: [app registration changes](https://learn.microsoft.com/en-us/entra/identity-platform/reference-breaking-changes),
  [device code flow](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code),
  [app folder](https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/special-folders-appfolder),
  [upload sessions](https://learn.microsoft.com/en-us/graph/api/driveitem-createuploadsession),
  [refresh tokens](https://learn.microsoft.com/en-us/entra/identity-platform/refresh-tokens),
  [tempauth retirement](https://devblogs.microsoft.com/microsoft365dev/pre-authenticated-tempauth-urls-are-retiring-move-to-microsoft-entra-id-tokens-before-april-1-2027/)
