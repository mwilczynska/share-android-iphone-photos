# Phase 0 runbook

Phase 0 answers three questions before the real app is built. See [iphone-app-plan.md](iphone-app-plan.md) for the
design. Record results in the tables at the end of each section; keep account names, IDs and links out of this file.

Status: the app compiles and its unit tests pass in GitHub's build. It has not yet been installed on a phone.

## 0a. Can a free-signed app stay alive on the phone?

**What exists**
- `app/`: a one-screen app that shows when its signature expires, how often it has been opened, and the iOS version.
- `ShortlistCore/`: the logic that reads the expiry date, with unit tests.
- `.github/workflows/build.yml`: tests, builds an unsigned `.ipa`, and publishes it to one of two channels.

**Build channels**

| Channel | Built from | Release page |
| --- | --- | --- |
| `test` | Every push to a branch other than `main` | `releases/tag/test-build` |
| `latest` | Every push to `main` | `releases/tag/latest-build` |

Each release holds `Shortlist.ipa` and `source.json` at fixed addresses:
`https://github.com/<owner>/<repo>/releases/download/<channel>-build/<file>`. A newer push to the same channel
replaces them. Both channels install the same app, so installing one replaces the other and keeps the app's data.
The app's screen shows which channel, commit and branch are installed.

**Steps**
1. Push to GitHub and wait for the Build workflow to pass.
2. On the Windows laptop, install iTunes from Apple's website (not the Store version), then run
   [iloader](https://github.com/nab138/iloader) with the iPhone connected by USB to install SideStore.
3. On the iPhone: trust the developer profile, turn on Developer Mode, install LocalDevVPN and connect it.
4. Open SideStore and sign in with the Apple Account chosen for signing, and refresh SideStore itself.
5. Add the test channel once by opening this in Safari on the iPhone:
   `sidestore://source?url=https://github.com/<owner>/<repo>/releases/download/test-build/source.json`.
   Install Shortlist from that source in SideStore.
6. If adding the source fails, install directly instead:
   `sidestore://install?url=https://github.com/<owner>/<repo>/releases/download/test-build/Shortlist.ipa`.
7. Open Shortlist. Note the expiry date, channel, commit and the iOS version it shows.
8. In the Shortcuts app, add a daily automation that runs SideStore's "Refresh All Apps" at a time when the phone is
   normally unlocked and on Wi-Fi.
9. Check the app every few days for two weeks. "Last signed" should move forward and "Times opened" should keep
   counting up.

**Installing a new version while iterating**
- Over the air: push to the branch, wait for the build (about 5 to 10 minutes), then in SideStore pull to refresh
  the source and tap Update. The phone needs Wi-Fi and LocalDevVPN connected. Each install restarts the 7-day clock.
- By cable: run `.\scripts\get-build.ps1` on the laptop (or `-Channel latest`), connect the phone, and open the
  downloaded file in iloader or Sideloadly. This works even when SideStore's own sign-in is failing.
- A manual run from the Actions tab (Build, "Run workflow", pick a branch) republishes that branch without a new
  commit.

**Unverified**
- Whether SideStore follows GitHub's redirect from a release download address to the file. If adding the source
  fails, try the direct install link, then the cable route.
- Whether SideStore matches the source's bundle identifier to the installed app after it appends its team ID. If
  updates never appear, use the direct install link for each build.

**Known problems on 21 November 2026**
- SideStore sign-in has been returning HTTP 503 since 20 November (open issues, no fix announced).
- Refresh is reported to fail while the phone is locked on iOS 27.2.
- If SideStore cannot be made to work, try Sideloadly with its Wi-Fi auto-refresh, then a weekly Run from Xcode.

**Results**

| Question | Answer |
| --- | --- |
| iOS version on the phone | |
| Installed with | |
| Refreshed without a computer, first week | |
| Refreshed without a computer, second week | |
| Data kept across a refresh | |
| Data kept across an app update | |
| Adding the source in SideStore works | |
| New builds appear as updates in SideStore | |

## 0b. Can a script upload to OneDrive with a folder-limited token?

This needs no phone.

**One-time Microsoft setup**
1. Create an Azure free account with the Microsoft account that owns the OneDrive.
2. In the Entra admin centre, register an application:
   - Supported account types: personal Microsoft accounts only.
   - Platform: mobile and desktop applications (no redirect URI is needed for this test).
   - Authentication: set "Allow public client flows" to Yes.
   - API permissions: Microsoft Graph, delegated, `Files.ReadWrite.AppFolder` and `offline_access`.
3. Save the application (client) ID in `private/onedrive.local.json`, which is gitignored:

   ```json
   { "clientId": "<application id>" }
   ```

**Run**

```powershell
.\scripts\onedrive-spike.ps1 -FilePath C:\path\to\a-photo.heic
```

The script prints a code and a Microsoft address. Approve it in a browser, then read the results table.

**Then check by hand**
- Run the same command again to see how a duplicate name is reported.
- Upload a video larger than 60 MiB to exercise multiple fragments.
- In OneDrive on the web, find `Apps/<app name>/spike/`: does the Photos view sort the file by its capture date?
- Share the app folder, or move it into the joint album folder, then run the script once more with a new file.
- If creating the upload session fails, repeat with `-Scope "Files.ReadWrite offline_access"`.

**Results**

| Question | Answer |
| --- | --- |
| Device-code sign-in works for a personal account | |
| `Files.ReadWrite.AppFolder` is enough for an upload session | |
| Upload works without an Authorization header | |
| Stored created and modified times match what was sent | |
| OneDrive extracts the taken date from HEIC | |
| Duplicate name is reported as | |
| Photos view sorts by capture date | |
| Folder still works after sharing or moving | |

## 0c. How fast is indexing on the phone?

Not built yet. It needs photo-library access and the embedding model, so it follows once 0a shows the app can be
installed. It will measure milliseconds per photo, memory use, and whether small images are available without
downloading originals when "Optimise iPhone Storage" is on.
