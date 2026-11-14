# Architecture

GarHub has a SwiftUI presentation target, a deterministic core library and an optional on-device intelligence module. All run on the Mac.

| Component | Responsibility |
| --- | --- |
| FIT importer | Validates bounded input, decodes recordings through the Garmin FIT SDK and preserves multisport session boundaries. |
| Activity store | Uses one SQLite actor for reads and writes. Archives original FIT files, keeps activity summaries and samples, and deduplicates by original-file hash. |
| Garmin client | Uses the Personal API with the key holder’s own account. Saves the key to macOS Keychain after verification. Tracks progress for resumable history imports. |
| Charts and comparisons | Inspect local sensor samples by elapsed time or recorded distance. Keep recorded timer and elapsed duration distinct and match repeated sports by occurrence. |
| Map | Filters outdoor GPS samples, draws the heat layer locally and queries nearby segments to find matching recordings. Apple Maps supplies the optional street basemap. |
| Performance | Time-weighted power integrals, continuous distance interpolation, running splits and paired speed/HR drift. |
| Plans and layouts | Bounded Codable preferences for local calendar plans and Home presets. Calendar settings are included in backup preferences. |
| Recovery | Completed-day training/health alignment, available-day rolling means and descriptive correlations. |
| Backups | Snapshots SQLite and originals, verifies hashes and schema on restore, and saves a recovery backup before replacement. |
| On-device highlights | Model-free core builds bounded comparison evidence. `TrainingHubIntelligence` explicitly selects Apple's local system model and validates returned fact IDs. SwiftUI displays only app-authored facts and limitations. |

There is no hosted activity database or background analytics service. Optional on-device AI is off by default and runs only on explicit request. Its module has no remote providers or network tools. The normal app remains usable on macOS 14 and when the model is unavailable. For network and data boundaries, see [Security and privacy](../SECURITY.md).
