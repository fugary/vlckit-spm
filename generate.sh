#!/bin/sh
#
# Automated VLCKit SPM package generator
# Usage: ./generate.sh <version>
# Example: ./generate.sh 3.7.2
#
set -e

rm -rf .tmp/ || true

# --- Resolve version ---
TAG_VERSION="${1:-$GITHUB_REF_NAME}"
if [ -z "$TAG_VERSION" ]; then
    echo "❌ Error: No version specified."
    echo "Usage: ./generate.sh <version>"
    echo "Example: ./generate.sh 3.7.2"
    exit 1
fi

# Strip 'v' prefix if present (e.g. v3.7.2 -> 3.7.2)
TAG_VERSION="${TAG_VERSION#v}"

GITHUB_REPO="${GITHUB_REPO:-fugary/vlckit-spm}"
BASE_URL="https://download.videolan.org/pub/cocoapods/prod/"

echo "🔍 Looking for VLCKit version ${TAG_VERSION} on ${BASE_URL} ..."

# --- Fetch directory listing and discover filenames ---
DIR_LISTING=$(curl -sfL "$BASE_URL")
if [ -z "$DIR_LISTING" ]; then
    echo "❌ Error: Failed to fetch directory listing from ${BASE_URL}"
    exit 1
fi

# Use grep + sed to extract filenames matching the version
# Pattern: {Prefix}-{version}-{hash1}-{hash2}.tar.xz
IOS_FILE=$(echo "$DIR_LISTING" | grep -o "MobileVLCKit-${TAG_VERSION}-[a-f0-9]*-[a-f0-9]*\.tar\.xz" | head -1)
MACOS_FILE=$(echo "$DIR_LISTING" | grep -o "\"VLCKit-${TAG_VERSION}-[a-f0-9]*-[a-f0-9]*\.tar\.xz" | sed 's/^"//' | head -1)
TVOS_FILE=$(echo "$DIR_LISTING" | grep -o "TVVLCKit-${TAG_VERSION}-[a-f0-9]*-[a-f0-9]*\.tar\.xz" | head -1)

# Validate all three were found
MISSING=""
if [ -z "$IOS_FILE" ]; then MISSING="${MISSING} MobileVLCKit"; fi
if [ -z "$MACOS_FILE" ]; then MISSING="${MISSING} VLCKit(macOS)"; fi
if [ -z "$TVOS_FILE" ]; then MISSING="${MISSING} TVVLCKit"; fi

if [ -n "$MISSING" ]; then
    echo "❌ Error: Could not find downloads for version ${TAG_VERSION}:"
    echo "   Missing:${MISSING}"
    echo ""
    echo "Available versions on VideoLAN:"
    echo "$DIR_LISTING" | grep -o "MobileVLCKit-[0-9][^\"]*\.tar\.xz" | sed 's/MobileVLCKit-//;s/-[a-f0-9]*-[a-f0-9]*\.tar\.xz//' | sort -V | uniq
    exit 1
fi

IOS_URL="${BASE_URL}${IOS_FILE}"
MACOS_URL="${BASE_URL}${MACOS_FILE}"
TVOS_URL="${BASE_URL}${TVOS_FILE}"

echo "✅ Found downloads:"
echo "   iOS:   ${IOS_FILE}"
echo "   macOS: ${MACOS_FILE}"
echo "   tvOS:  ${TVOS_FILE}"
echo ""

# --- Download ---
mkdir .tmp/

echo "⬇️  Downloading MobileVLCKit..."
curl -L -o .tmp/MobileVLCKit.tar.xz "$IOS_URL"
tar -xf .tmp/MobileVLCKit.tar.xz -C .tmp/

echo "⬇️  Downloading VLCKit..."
curl -L -o .tmp/VLCKit.tar.xz "$MACOS_URL"
tar -xf .tmp/VLCKit.tar.xz -C .tmp/

echo "⬇️  Downloading TVVLCKit..."
curl -L -o .tmp/TVVLCKit.tar.xz "$TVOS_URL"
tar -xf .tmp/TVVLCKit.tar.xz -C .tmp/

# --- Locate xcframeworks ---
IOS_LOCATION=".tmp/MobileVLCKit-binary/MobileVLCKit.xcframework"
TVOS_LOCATION=".tmp/TVVLCKit-binary/TVVLCKit.xcframework"
MACOS_LOCATION=".tmp/VLCKit - binary package/VLCKit.xcframework"

# --- Merge into one xcframework ---
echo "🔧 Creating unified xcframework..."
xcodebuild -create-xcframework \
    -framework "$MACOS_LOCATION/macos-arm64_x86_64/VLCKit.framework" \
    -debug-symbols "${PWD}/$MACOS_LOCATION/macos-arm64_x86_64/dSYMs/VLCKit.framework.dSYM" \
    -framework "$TVOS_LOCATION/tvos-arm64_x86_64-simulator/TVVLCKit.framework" \
    -debug-symbols "${PWD}/$TVOS_LOCATION/tvos-arm64_x86_64-simulator/dSYMs/TVVLCKit.framework.dSYM" \
    -framework "$TVOS_LOCATION/tvos-arm64/TVVLCKit.framework"  \
    -debug-symbols "${PWD}/$TVOS_LOCATION/tvos-arm64/dSYMs/TVVLCKit.framework.dSYM" \
    -framework "$IOS_LOCATION/ios-arm64_i386_x86_64-simulator/MobileVLCKit.framework" \
    -debug-symbols "${PWD}/$IOS_LOCATION/ios-arm64_i386_x86_64-simulator/dSYMs/MobileVLCKit.framework.dSYM" \
    -framework "$IOS_LOCATION/ios-arm64_armv7_armv7s/MobileVLCKit.framework" \
    -debug-symbols "${PWD}/$IOS_LOCATION/ios-arm64_armv7_armv7s/dSYMs/MobileVLCKit.framework.dSYM" \
    -output .tmp/VLCKit-all.xcframework

echo "📦 Compressing xcframework..."
ditto -c -k --sequesterRsrc --keepParent ".tmp/VLCKit-all.xcframework" ".tmp/VLCKit-all.xcframework.zip"

# --- Update Package.swift ---
# Use shasum (works on both macOS and Linux)
if command -v shasum > /dev/null 2>&1; then
    PACKAGE_HASH=$(shasum -a 256 ".tmp/VLCKit-all.xcframework.zip" | awk '{ print $1 }')
elif command -v sha256sum > /dev/null 2>&1; then
    PACKAGE_HASH=$(sha256sum ".tmp/VLCKit-all.xcframework.zip" | awk '{ print $1 }')
else
    echo "❌ Error: Neither shasum nor sha256sum found"
    exit 1
fi

PACKAGE_STRING="Target.binaryTarget(name: \"VLCKit-all\", url: \"https://github.com/${GITHUB_REPO}/releases/download/${TAG_VERSION}/VLCKit-all.xcframework.zip\", checksum: \"${PACKAGE_HASH}\")"
echo "📝 Updating Package.swift (hash: ${PACKAGE_HASH})"
sed -i '' -e "s|let vlcBinary.*|let vlcBinary = ${PACKAGE_STRING}|" Package.swift

# --- Auto-detect platform minimum versions from frameworks ---
echo "🔍 Detecting platform minimum versions..."

# Helper: read MinimumOSVersion from a framework's Info.plist
get_min_version() {
    local plist="$1/Info.plist"
    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist" 2>/dev/null || \
        echo ""
    fi
}

# Helper: convert version like "12.0" to SPM enum like ".v12"
# SPM uses .v11, .v12, .v13 etc for iOS; .v10_13, .v10_15, .v11 etc for macOS
version_to_spm() {
    local platform="$1"
    local version="$2"
    local major minor

    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    minor=${minor:-0}

    if [ "$platform" = "macOS" ]; then
        if [ "$major" -eq 10 ]; then
            echo ".v10_${minor}"
        else
            echo ".v${major}"
        fi
    else
        if [ "$minor" -eq 0 ]; then
            echo ".v${major}"
        else
            echo ".v${major}"
        fi
    fi
}

IOS_MIN=$(get_min_version "$IOS_LOCATION/ios-arm64_armv7_armv7s/MobileVLCKit.framework")
if [ -z "$IOS_MIN" ]; then
    IOS_MIN=$(get_min_version "$IOS_LOCATION/ios-arm64/MobileVLCKit.framework")
fi
MACOS_MIN=$(get_min_version "$MACOS_LOCATION/macos-arm64_x86_64/VLCKit.framework")
TVOS_MIN=$(get_min_version "$TVOS_LOCATION/tvos-arm64/TVVLCKit.framework")

if [ -n "$IOS_MIN" ] && [ -n "$MACOS_MIN" ] && [ -n "$TVOS_MIN" ]; then
    IOS_SPM=$(version_to_spm "iOS" "$IOS_MIN")
    MACOS_SPM=$(version_to_spm "macOS" "$MACOS_MIN")
    TVOS_SPM=$(version_to_spm "tvOS" "$TVOS_MIN")

    echo "   iOS:   ${IOS_MIN} → ${IOS_SPM}"
    echo "   macOS: ${MACOS_MIN} → ${MACOS_SPM}"
    echo "   tvOS:  ${TVOS_MIN} → ${TVOS_SPM}"

    PLATFORMS_STRING="platforms: [.macOS(${MACOS_SPM}), .iOS(${IOS_SPM}), .tvOS(${TVOS_SPM})],"
    sed -i '' -e "s|platforms:.*|${PLATFORMS_STRING}|" Package.swift
else
    echo "⚠️  Could not detect platform versions, keeping existing values"
    echo "   iOS=[${IOS_MIN}] macOS=[${MACOS_MIN}] tvOS=[${TVOS_MIN}]"
fi

# --- Copy license ---
cp -f .tmp/MobileVLCKit-binary/COPYING.txt ./LICENSE

echo ""
echo "🎉 Done! VLCKit ${TAG_VERSION} package generated successfully."
echo "   xcframework: .tmp/VLCKit-all.xcframework.zip"
echo "   Package.swift updated with new checksum."
