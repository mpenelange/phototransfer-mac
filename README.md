# Photo Transfer

A small native macOS app for safely importing camera files. It scans an SD card or mounted camera volume, sends Nikon NEF and JPEG files to separate folders, verifies every copy, and can then remove the verified originals.

The app icon depicts an SD card splitting an import into two destination folders. Its complete macOS icon set lives in `Sources/PhotoTransfer/Resources/Assets.xcassets`.

## Run it

Requirements: macOS 14 or later and Xcode 16 or later.

1. Open `PhotoTransfer.xcodeproj` in Xcode.
2. Select the **PhotoTransfer** scheme and **My Mac**.
3. Press Run.

You can also launch a debug build from Terminal:

```sh
swift run
```

## Build a macOS app

Create a local, ad-hoc signed release app:

```sh
zsh Scripts/build-app.sh
```

The result is `dist/PhotoTransfer.app`.

For an Xcode archive that uses your Apple Developer team, replace the example with your 10-character Team ID:

```sh
DEVELOPMENT_TEAM=ABCDE12345 zsh Scripts/archive.sh
open dist/PhotoTransfer.xcarchive
```

Xcode Organizer can then export the archive with a Developer ID certificate and submit it for notarization.

For an entirely command-line workflow, archive first and then run:

```sh
DEVELOPMENT_TEAM=ABCDE12345 zsh Scripts/export-developer-id.sh
xcrun notarytool store-credentials PhotoTransferNotary \
  --apple-id "you@example.com" \
  --team-id ABCDE12345
zsh Scripts/notarize.sh
```

`store-credentials` prompts for the app-specific password and stores it in Keychain; no signing or notarization secret is placed in this repository. The notarization script submits the Developer ID export, waits for Apple, staples the ticket, and validates it with Gatekeeper.

## Workflow

1. Insert the SD card or connect a camera that appears as a mounted volume in Finder.
2. Choose it under **Detected Devices**. If it is not listed, choose its `DCIM` folder manually.
3. Choose separate destination folders for NEF and JPEG files.
4. Decide whether movies and other files go to one of those destinations or are skipped.
5. Scan and review the counts.
6. Transfer. If deletion is enabled, confirm the destructive step.

Optionally enable **Unmount and eject card after successful transfer**. The app ejects only when every file operation succeeds; it deliberately leaves the card mounted if copying, verification, or original deletion reports an issue.

Each import is placed in a subfolder named for the local import date, such as `2026-08-18`, under both selected destinations. The app copies into a temporary file, compares the source and destination using SHA-256, moves the verified file into place, and only then deletes that individual original. A failed copy never triggers deletion. Identical files from a prior run are recognized, and different files with the same name receive `-2`, `-3`, and so on.

## Camera compatibility

This version supports SD cards, card readers, and cameras that macOS exposes as normal mounted filesystems. Cameras available only through PTP/Image Capture do not expose source file URLs and need a separate `ImageCaptureCore` import path; for those, use a card reader for now.

## Tests

```sh
swift test
```

The tests use temporary folders and cover extension classification, NEF/JPEG routing, collisions, repeat imports, verified deletion, and source/destination overlap protection.
