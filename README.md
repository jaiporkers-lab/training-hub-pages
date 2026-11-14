# GarHub for macOS

GarHub is a local-first SwiftUI companion for Garmin recordings. Import original FIT files or connect your own Garmin account, then inspect any supported activity, compare efforts, plan your training and explore outdoor routes. Running, cycling, swimming, hiking, strength and multisport recordings share one library. Available analysis depends on the fields your device records.

[Website & download](https://jaiporkers-lab.github.io/training-hub-pages/) · [Build and test](docs/BUILDING.md) · [Changelog](CHANGELOG.md) · [Security and privacy](SECURITY.md) · [Feature guide](docs/FEATURES.md)

## What you can do

- Inspect fast hover charts, laps, custom zones and original FIT statistics. Expand multisport recordings into individual legs. Review pool lengths, rests, strokes and SWOLF when recorded.
- Compare activities and matched multisport legs by time or distance, with simultaneous cursor readouts.
- Analyse running kilometre splits, steady-section HR drift with coverage checks, and best distance efforts.
- Review cycling power curves from 5 seconds to 60 minutes, excluding recording gaps. Set your own FTP for percentages.
- Plan workouts and race dates on a weekly calendar, drag to reschedule, and open completed activities beside them.
- Set weekly time/distance goals and a library distance milestone. Scan local recordings for running and cycling best efforts.
- Explore a personal outdoor heatmap over an optional Apple Maps basemap. Hover to count nearby activities, pin a location and open a recording. Indoor and virtual sessions are excluded.
- Colour individual routes by HR, pace, power or elevation. Inspect elevation profiles and detected climbs, find approximately matching routes and compare profiles.
- Align training and health history. Review 7-day rolling trends, recent versus preceding averages and descriptive same-day or next-day associations, with coverage counts.
- Use Home presets for running, cycling, swimming, triathlon and recovery, or save your own card/sport layout.
- Follow the live in-app tour, including the new features, and replay it from the toolbar. Connect Garmin or import files during welcome setup.
- Export CSVs, create verified local backups, and prepare a coaching brief locally.
- Optionally enable **Settings → On-device AI** for comparison highlights. AI is off by default, runs only on this Mac and selects verified facts; there are no AI API charges or cloud fallbacks. Requires macOS 26+ and an available Apple on-device model. [Details and current scope](docs/ON-DEVICE-AI.md)

## Get started

Download the [Apple silicon disk image](https://jaiporkers-lab.github.io/training-hub-pages/downloads/GarHub-0.9.0-arm64.dmg) for macOS 14 or later and drag **GarHub** into Applications. The build is ad-hoc signed and is not Apple-notarised. See [checksums](downloads/SHA256SUMS.txt) and the [installation notes](docs/BUILDING.md).

On the welcome screen, connect your own Garmin account or continue to FIT import. The Garmin Personal API settings link explains how to create a key. Paste it in **Personal API key**, then choose **Save & test connection**. GarHub verifies it with Garmin and stores it in macOS Keychain. You can do this later in **Settings → Garmin**. Availability is controlled by Garmin. [Garmin Personal API FAQ](https://developer.garmin.com/gc-developer-program/personal/personal-faq)

After setup, **Start live app tour** opens each working section with guidance beneath it. You can interact with the app, go back, end the tour or revisit the section. Empty libraries receive guidance without fabricated activities.

## Build from source

Use a Mac with Xcode and Swift 6. The on-device AI adapter uses the Foundation Models SDK in Xcode 26 or later; the app keeps its macOS 14 baseline. Older SDK builds omit that adapter. Swift Package Manager fetches the pinned dependencies from their upstream repositories.

```sh
swift test --build-system native
zsh scripts/build-app.sh
zsh scripts/build-dmg.sh
```

The scripts produce `../GarHub.zip` and `../GarHub-<version>-<architecture>.dmg`. See the [build guide](docs/BUILDING.md) for complete instructions.

## Repository guide

| Path | Contents |
| --- | --- |
| [Sources/TrainingHubApp](Sources/TrainingHubApp) | SwiftUI screens, onboarding, maps and chart interaction |
| [Sources/TrainingHubCore](Sources/TrainingHubCore) | FIT import, SQLite, Garmin sync and local analysis |
| [Tests](Tests) | Synthetic fixtures and regression checks |
| [docs](docs) | Build guide, feature guide and architecture |
| [scripts](scripts) | App, disk-image and icon packaging |
| [index.html](index.html) | Public website; no training-data backend |

GarHub is an independent, vibe-coded personal project. It is not affiliated with or certified by Garmin and has not had an independent security audit. The source and checks are provided for inspection; they are not a security guarantee. Read the [third-party notices](THIRD_PARTY_NOTICES.md) before distributing a build.

## Licence

GarHub’s original code and documentation are licensed under the [MIT License](LICENSE). You may use, modify and redistribute that code, including commercially, provided you retain the copyright and licence notice. It is supplied without warranty.

Third-party components keep their own licences; the MIT licence does not relicense Garmin’s FIT SDK, Swift Collections or other upstream material. Review [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before redistributing a build. Licensing does not imply an independent security audit or Garmin endorsement.
