# Build and test Training Hub

Install Xcode and select its command-line tools. Use a Swift 6 toolchain. The app targets macOS 14 or later. The scripts build for the Mac running the command.

```sh
git clone https://github.com/jaiporkers-lab/training-hub-pages.git training-hub
cd training-hub
swift test --build-system native
zsh scripts/build-app.sh
zsh scripts/build-dmg.sh
```

- Swift Package Manager resolves the official Garmin FIT SDK and its dependencies using `Package.resolved`.
- The app script writes `../Garmin Training Hub.zip`. The disk-image script reads that archive and writes `../Training-Hub-<version>-<architecture>.dmg`.
- Open the disk image and drag **Garmin Training Hub** into Applications. The scripts produce a local ad-hoc build. For distribution, review the dependency terms and Apple's Developer ID and notarisation requirements. [Apple notarisation guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

The default tests use isolated libraries and synthetic activities. Tests for original files are optional. To run them, set `TRAINING_HUB_TEST_FIT`, `TRAINING_HUB_TEST_ZIP` or `TRAINING_HUB_TEST_POOL` to your own reproduction files. Keep those recordings outside the repository.

`swift run --build-system native hub-check /tmp/training-hub-check` exercises the import and storage pipeline with generated fixtures. For app development with an isolated library, set `TRAINING_HUB_DATA_DIR` to an empty directory when launching the executable. Garmin credentials are managed separately by macOS Keychain.
