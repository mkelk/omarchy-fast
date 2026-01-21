# Android Emulator Installation Log - 2026-01-21

## Summary

**Status: SUCCESS** - Android emulator is working and migration updated.

## Changes Made

### Migration Updated: `0000000099_setup_android_development.sh`

Updated to use:
- **Android 35** (was Android 34)
- **Google Play Store** system image (was plain google_apis)
- **Pixel 8** device profile (was Pixel 6)
- **QT_QPA_PLATFORM=xcb** added to ~/.bashrc for Wayland/Hyprland compatibility

### Key Configuration

After running the migration, projects can use the emulator without special knowledge:

```bash
# Start emulator (after sourcing ~/.bashrc or new shell)
emulator -avd Pixel8_API35

# Check devices
adb devices

# Connect to emulator
adb shell
```

### Environment Variables (set in ~/.bashrc)

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export QT_QPA_PLATFORM="xcb"  # Required for Wayland/Hyprland
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:..."
```

## Current Working Setup

**Emulator running:**
- AVD Name: Pixel8_API35
- Device Profile: Pixel 8
- Android Version: 15 (API 35)
- System Image: google_apis_playstore/x86_64
- ADB Device: emulator-5554

## Notes

1. **GPU:** Uses SwANGLE (software rendering) - GPU was denylisted but still works
2. **KVM:** Hardware acceleration via KVM is working
3. **Wayland/Hyprland:** `QT_QPA_PLATFORM=xcb` forces XWayland since emulator lacks Qt wayland plugin
4. **ADB:** Start server with `adb start-server` if needed

## For Projects (e.g., self-v4)

Just use standard Android commands - no special setup needed:

```bash
# Run tests on emulator
./gradlew connectedAndroidTest

# Install APK
adb install app.apk

# View logs
adb logcat
```

The migration ensures all environment variables are set correctly in ~/.bashrc.
