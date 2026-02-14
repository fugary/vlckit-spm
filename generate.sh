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

PACKAGE_STRING="Target.binaryTarget(name: \"VLCKit-all\", url: \"https:\/\/github.com\/${GITHUB_REPO}\/releases\/download\/${TAG_VERSION}\/VLCKit-all.xcframework.zip\", checksum: \"${PACKAGE_HASH}\")"
echo "📝 Updating Package.swift (hash: ${PACKAGE_HASH})"
sed -i '' -e "s/let vlcBinary.*/let vlcBinary = ${PACKAGE_STRING}/" Package.swift

# --- Copy license ---
cp -f .tmp/MobileVLCKit-binary/COPYING.txt ./LICENSE

echo ""
echo "🎉 Done! VLCKit ${TAG_VERSION} package generated successfully."
echo "   xcframework: .tmp/VLCKit-all.xcframework.zip"
echo "   Package.swift updated with new checksum."
