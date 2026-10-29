#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/clang build
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang"
if [[ "${1:-}" == "--xcode" ]]; then
    xcodebuild -project FujiFrame.xcodeproj -scheme FujiFrame -configuration Release -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' build CODE_SIGN_IDENTITY=-
    /usr/bin/ditto build/DerivedData/Build/Products/Release/FujiFrame.app build/FujiFrame.app
else
    swift build --disable-sandbox --cache-path .build/cache -c release --product FujiFrame
    mkdir -p build/FujiFrame.app/Contents/MacOS build/FujiFrame.app/Contents/Resources
    cp .build/release/FujiFrame build/FujiFrame.app/Contents/MacOS/FujiFrame
    /usr/bin/plutil -create xml1 build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert CFBundleExecutable -string FujiFrame build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert CFBundleIdentifier -string local.FujiFrame build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert CFBundleName -string FujiFrame build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert CFBundleDisplayName -string FujiFrame build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert CFBundlePackageType -string APPL build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert CFBundleShortVersionString -string 1.0.0 build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert CFBundleVersion -string 1 build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert NSHighResolutionCapable -bool YES build/FujiFrame.app/Contents/Info.plist
    /usr/bin/plutil -insert LSApplicationCategoryType -string public.app-category.photography build/FujiFrame.app/Contents/Info.plist
    /usr/bin/codesign --force --sign - --options runtime build/FujiFrame.app
fi
/usr/bin/codesign --verify --deep --strict build/FujiFrame.app
