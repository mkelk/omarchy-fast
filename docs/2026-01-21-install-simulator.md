# Android Emulator Setup - Omarchy (Arch Linux)

## Summary

**Status: SUCCESS** - Android emulator working for E2E testing with Maestro.

## Quick Start (Copy-Paste)

```bash
# Start emulator (handles non-standard AVD location + Wayland)
ANDROID_AVD_HOME=~/.config/.android/avd QT_QPA_PLATFORM=xcb \
  /opt/android-sdk/emulator/emulator -avd Pixel8_API35 &

# Wait for boot and verify
sleep 10 && adb devices  # Should show: emulator-5554    device

# Install Maestro (one-time)
curl -Ls "https://get.maestro.mobile.dev" | bash
export PATH="$PATH:$HOME/.maestro/bin"

# Run E2E tests (from project directory)
~/.maestro/bin/maestro test e2e/flows/onboarding/simple-flow.yaml
```

## Configuration Details

### Emulator Setup (via migration `0000000099_setup_android_development.sh`)

| Setting | Value |
|---------|-------|
| AVD Name | `Pixel8_API35` |
| Device Profile | Pixel 8 |
| Android Version | 15 (API 35) |
| System Image | `google_apis_playstore/x86_64` |
| ADB Device ID | `emulator-5554` |

### Key Paths

| Component | Location |
|-----------|----------|
| Emulator binary | `/opt/android-sdk/emulator/emulator` |
| AVD directory | `~/.config/.android/avd/` |
| ADB | System `adb` (from `android-tools` package) |
| Maestro | `~/.maestro/bin/maestro` |

### Required Environment Variables

Set in `~/.bashrc` by the migration:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export QT_QPA_PLATFORM="xcb"  # Required for Wayland/Hyprland
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
```

**Note:** AVD is in non-standard location (`~/.config/.android/avd/`), so must set `ANDROID_AVD_HOME` when starting emulator.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Emulator won't start | Set `QT_QPA_PLATFORM=xcb` (Qt lacks Wayland plugin) |
| AVD not found | Set `ANDROID_AVD_HOME=~/.config/.android/avd` |
| `adb devices` empty | Wait for boot or run `adb start-server` |
| GPU errors | Uses SwANGLE (software) - GPU was denylisted, still works |
| maestro not found | Add `~/.maestro/bin` to PATH |

## For Projects (e.g., self-v4)

### Standard Android Commands
```bash
# Install APK
adb install android/app/build/outputs/apk/play/release/app-play-release.apk

# View logs
adb logcat

# Run Gradle tests
./gradlew connectedAndroidTest
```

### E2E Testing with Maestro
```bash
# Build release APK (debug won't work with clearState)
cd android && ./gradlew assemblePlayRelease && cd ..

# Install and run test
adb install android/app/build/outputs/apk/play/release/app-play-release.apk
~/.maestro/bin/maestro test e2e/flows/onboarding/simple-flow.yaml
```

See `self-v4/e2e/README.md` and `self-v4/docs/current/ui-testing.md` for comprehensive E2E testing documentation.

## Technical Notes

1. **GPU:** SwANGLE (software rendering) - GPU was denylisted but emulator still works
2. **KVM:** Hardware acceleration via KVM is working
3. **Wayland/Hyprland:** `QT_QPA_PLATFORM=xcb` forces XWayland since emulator lacks Qt wayland plugin
4. **ADB:** Available via system package (`android-tools`), no PATH issues
