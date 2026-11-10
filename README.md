# Training Hub for macOS

Training Hub is a local-first SwiftUI training log. Import an original FIT recording or connect your own Garmin account, then inspect the activity, compare efforts, or explore your outdoor routes on a heatmap.

[Project website](https://jaiporkers-lab.github.io/training-hub-pages/) · [Build and test](docs/BUILDING.md) · [Changelog](CHANGELOG.md) · [Security and privacy](SECURITY.md)

## What you can do

- Open a whole triathlon or inspect its swim, bike, run and transitions individually.
- Inspect charts by time or distance, analyse laps and zones, and compare activities or matched race legs. View original FIT statistics and individual pool lengths when recorded.
- Explore the outdoor heatmap. Hover to count nearby recordings, then click a spot to open an activity from the list. Indoor and virtual routes are excluded.
- Customise Home and the activity feed, compare training volume and supported health metrics, and create local backups or CSV exports.
- Prepare a coaching brief locally. Copy it yourself when you want to use it in a chat.

## Get started

Build the app on a Mac with Xcode and Swift 6. The package targets macOS 14 or later. Swift Package Manager fetches the pinned dependencies from their upstream repositories.

```sh
swift test --build-system native
zsh scripts/build-app.sh
zsh scripts/build-dmg.sh
```

The last command makes a disk image for local use beside the checkout. See the [build guide](docs/BUILDING.md) for exact output paths and packaging requirements.

On the welcome screen, choose **Import FIT** during setup or connect your own Garmin account. To connect, open the Garmin Personal API settings link, sign in, create a key, then paste it into **Personal API key** and choose **Save & test connection**. Training Hub verifies it with Garmin and stores it in macOS Keychain. You can also do this later in **Settings → Garmin**. [Garmin Personal API FAQ](https://developer.garmin.com/gc-developer-program/personal/personal-faq)

## Repository guide

| Path | Contents |
| --- | --- |
| [Sources/TrainingHubApp](Sources/TrainingHubApp) | SwiftUI screens, onboarding, map and chart interaction |
| [Sources/TrainingHubCore](Sources/TrainingHubCore) | FIT import, SQLite library, Garmin sync and local analysis |
| [Tests](Tests) | Synthetic fixtures and regression tests |
| [docs](docs) | Build guide and architecture |
| [scripts](scripts) | App, disk-image and icon packaging |

Training Hub is an independent, AI-assisted personal project. This repository contains the project source and references upstream dependencies. It is not affiliated with Garmin. Read the [third-party notices](THIRD_PARTY_NOTICES.md) before distributing a build.
