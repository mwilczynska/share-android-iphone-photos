# share-android-iphone-photos

Working out a low-effort, no-cost way for two people to share selected photos when one uses Android, Windows and
OneDrive and the other uses an iPhone, a Mac and iCloud.

- [Research report](reports/Android%20iPhone%20photo%20sharing%20options.md): the ready-made options and why most
  fall short.
- [App plan](docs/iphone-app-plan.md): a small iPhone app that learns which photos to share and uploads them to
  OneDrive.
- [Phase 0 runbook](docs/phase-0.md): the three tests that decide whether the app is worth building.

## Layout

| Path | Contents |
| --- | --- |
| `app/` | iOS app sources and the XcodeGen project definition |
| `ShortlistCore/` | Platform-independent Swift package with unit tests |
| `scripts/` | Test scripts that run on Windows |
| `.github/workflows/` | Build that compiles the app without signing it |

This repository is public. Account identifiers, links, signing material, photos and anything derived from them stay
out of it; see the privacy section of the app plan and `.gitignore`.
