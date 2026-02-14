# VLCKit SPM

This is a Swift Package Manager compatible version of [VLCKit](https://code.videolan.org/videolan/VLCKit). 
It distributes and bundles VLCKit for iOS, macOS and tvOS as a single Swift Package. 

### Installation
Add this repo to as a Swift Package dependency to your project
```
https://github.com/fugary/vlckit-spm
```

If using this in a swift package, add this repo as a dependency.
```
.package(url: "https://github.com/fugary/vlckit-spm/", .upToNextMajor(from: "3.6.0"))
```

### Usage

To get started, import this library: `import VLCKitSPM`

See the [VLCKit documentation](https://videolan.videolan.me/VLCKit/) for more info on integration and usage for VLCKit.

### Automated Releases

This project uses GitHub Actions to automate releases. To publish a new version:

1. Push a tag matching the VLCKit version on [VideoLAN](https://download.videolan.org/pub/cocoapods/prod/):
   ```bash
   git tag 3.7.2
   git push origin 3.7.2
   ```
2. GitHub Actions will automatically:
   - Download MobileVLCKit, VLCKit, and TVVLCKit from VideoLAN
   - Merge them into a unified xcframework
   - Create a GitHub Release with the xcframework attached
   - Update `Package.swift` with the new checksum

### Building Manually
If you would like to bundle your own VLCKit binaries, run the `generate.sh` script:
```bash
./generate.sh 3.7.2
```
