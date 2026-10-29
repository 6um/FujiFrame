# FujiFrame

**Keep your Fujifilm X-T5 recipes and JPEG samples together.**

FujiFrame is a local, offline macOS app for organizing camera recipes and the photos taken with them. Record film simulation, white balance, and other settings; preserve each revision; and link sample photos to the exact recipe version used.

Built with SwiftUI, SQLite, and ImageIO. No third-party runtime dependencies, account, or cloud connection required.

## Features

| Feature | What you can do |
| --- | --- |
| Recipes and version history | Record camera settings, firmware, exposure notes, and source links. Changes to settings create a new version while preserving previous settings and photo associations. Duplicate, archive, and restore recipes. |
| Smart import with review | Select or drag in multiple JPEGs, read local Fujifilm metadata, and review suggested recipe matches. Assign photos individually or in batches, select historical versions, or exclude photos before confirming. |
| Photo browsing and search | Browse by recipe and version; search names, descriptions, or filenames; filter by film simulation and capture date. Zoom, pan, and navigate photos with the arrow keys. |
| Capture information | Inspect aperture, shutter speed, ISO, focal length, lens, capture time, and image dimensions. Missing values remain unknown. |
| Original preservation and deduplication | Copy original JPEGs without rewriting EXIF or color profiles. Deduplicate by content hash and associate one original with multiple recipe versions. |
| Library backup and restore | Back up the database and linked originals to a separate folder, verify integrity on restore, or move the entire library. |

Recipes organize your shooting records. They do not write settings back to the camera or apply filters to photos. Smart import suggestions always require your confirmation.

## Install and launch

### 1. Prepare your Mac

- **macOS 14 or later on an Apple Silicon Mac (M-series chip).** Intel Macs have not been verified.
- **A macOS development toolchain with Swift 5.9 or later.** The default build uses Swift Package Manager; an Apple Developer account is not required.

If you have not installed Apple's command line developer tools, open Terminal and run:

```bash
xcode-select --install
```

Follow the system prompts to finish installation. If the tools are already installed, continue. Check that Swift is available:

```bash
swift --version
xcrun --find swift
```

If Swift is missing or too old, install a newer version of the command line developer tools or Xcode compatible with your macOS version before building.

### 2. Download the source and build

The current installation method is to **build the app on your own Mac**. This source repository does not include a prebuilt `.app` or `.dmg`; downloading the source alone does not install the app.

Run these commands in Terminal:

```bash
git clone https://github.com/6um/FujiFrame.git
cd FujiFrame
./scripts/build-app.sh
open build/FujiFrame.app
```

After a successful build, the app is available at `build/FujiFrame.app` inside the repository. Allow the first compilation to finish. If the build fails, check the error reported in Terminal before continuing.

Alternatively, choose **Code → Download ZIP** on GitHub and extract the archive. In Terminal, type `cd ` (including the trailing space), drag the extracted folder into the Terminal window, and press Return. Then run:

```bash
./scripts/build-app.sh
open build/FujiFrame.app
```

### 3. Move the app to Applications

After building, open the output folder:

```bash
open build
```

Drag **FujiFrame.app** from Finder into your **Applications** folder. You can then launch it by double-clicking it there. Quit any running copy of FujiFrame before moving the app or replacing an older version.

The build script applies a local ad-hoc signature. The app is not Developer ID signed or notarized by Apple, and the current workflow is intended for building and running on your own Mac. If macOS blocks launch, check the app's source and build result first; do not disable system security protections to install it.

**Your library is stored separately from the app.** Moving or replacing the `.app` does not move your library. Keep the folder you selected when creating the library, and use the in-app backup feature regularly.

### Update the app

If you installed from a Git clone, quit FujiFrame, open Terminal in the original repository folder, and run:

```bash
git pull --ff-only
./scripts/build-app.sh
```

Copy the newly built `build/FujiFrame.app` into Applications again. If you downloaded a ZIP, download the updated source and rebuild instead. Back up your library before updating.

## First use

The current app interface is in Chinese. The labels below help you locate the main actions.

1. **Create a library:** click “创建我的资料库” (Create My Library) and choose a new folder. The suggested location is `Pictures/FujiFrame Library`. Use “打开资料库” (Open Library) for an existing library.
2. **Record a recipe:** click `+` in the sidebar and enter a name and camera settings. Parameters start as “未记录” (Not Recorded); fill them in using your actual camera settings.
3. **Import JPEG samples:** click “智能导入” (Smart Import) or drag multiple JPEGs from Finder. Review suggestions, manually assign unresolved photos to a recipe version or exclude them, then click “确认导入” (Confirm Import).
4. **Browse photos:** select a recipe and version, then click a sample to inspect its capture information. Use the expand button at the top right for the larger viewer and the left/right arrow keys to navigate.
5. **Back up your library:** use “资料库 → 备份资料库” (Library → Back Up Library) at the bottom left and choose a new destination folder name that does not already exist.

Smart matching considers only the latest versions of unarchived recipes. Missing metadata, ambiguous candidates, or failure to meet the strict matching criteria require manual assignment. See the [user guide (Chinese)](docs/USER_GUIDE.md) for review rules, batch operations, and backup and restore details.

## Status and limitations

- 30 automated tests and a desktop import workflow with synthetic JPEGs have passed. **Metadata recognition has not yet been validated against real X-T5 camera JPEGs.** Values that cannot be read reliably remain unknown; check suggested matches during review.
- Automatic Fujifilm recipe metadata parsing currently targets the X-T5. JPEGs from other cameras can be assigned manually; automatic recognition is not guaranteed.
- RAF, HEIF, creating recipes from photos, image editing, and cloud sync are not currently supported.
- Intel Macs, full-disk conditions, and very large photo libraries have not been validated. The Xcode project build path has not been fully verified in the current development environment; use the default build script above.
- The app interface and detailed documentation are currently in Chinese; this English README does not imply an English UI is available.

## Documentation and development

- [User guide (Chinese)](docs/USER_GUIDE.md): recipe versions, import review, search, photo management, backups, and restoration.
- [Metadata reference (Chinese)](docs/FUJI_METADATA.md): Fujifilm MakerNotes fields, strict matching criteria, and known limitations.
- [Development and validation notes (Chinese)](docs/DEVELOPMENT.md): project structure, Xcode builds, test coverage, and local validation results.

Run the automated tests from the repository root:

```bash
./scripts/test.sh
```
