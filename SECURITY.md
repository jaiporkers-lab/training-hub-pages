# Security and privacy

- Garmin keys are stored in macOS Keychain. Bearer tokens stay in memory. The Garmin client checks the HTTPS destination before sending credentials and disables redirects.
- Original FIT recordings and activity and health data are stored on the Mac. The app bounds FIT reads, validates FIT integrity, and checks ZIP paths, lengths and CRCs.
- Backup restore validates a privately staged database and its originals before replacement. Backup hashes detect file changes. Backup folders and exports should be kept private.
- Apple Maps can receive the area you view when the street basemap is on. Route drawing and inspection run locally. You can turn the basemap off in Map or during welcome setup. [Apple Maps privacy](https://www.apple.com/legal/privacy/data/en/apple-maps/)
- The prompt builder shows the text before copying and leaves health data out unless selected. Sensor CSVs omit GPS.

The project has automated regression tests and manual checks. It has had no independent security audit. The local build uses ad-hoc signing. Check the [build guide](docs/BUILDING.md) for packaging details.

For security reports, contact the repository owner privately. For ordinary bug reports, share the app version, macOS version and synthetic reproduction steps. Keep keys, activity files, backups, GPS locations and diagnostic logs with personal information out of public issues.
