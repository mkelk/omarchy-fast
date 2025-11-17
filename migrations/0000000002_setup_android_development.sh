#!/bin/bash
set -eEo pipefail

echo "melk: Android development setup (Arch Linux)"

# Config
ANDROID_SDK_ROOT_DEFAULT="$HOME/Android/Sdk"
AVD_NAME="${AVD_NAME:-Pixel_6_API_34}"
SYS_IMAGE="${SYS_IMAGE:-system-images;android-34;google_apis;x86_64}"
PLATFORM="${PLATFORM:-platforms;android-34}"
BUILD_TOOLS="${BUILD_TOOLS:-build-tools;34.0.0}"
START_EMULATOR="${START_EMULATOR:-false}"

# Android Studio (AUR)
echo "melk: Install Android Studio"
if ! command -v android-studio &>/dev/null; then
  echo "Installing Android Studio from AUR..."
  yay -Sy --noconfirm android-studio || { echo "Failed to install Android Studio"; exit 1; }
  sudo updatedb || true
else
  echo "Android Studio already installed"
fi
echo "✓ Android Studio installation step complete"

# JDK (needed for sdkmanager/Gradle)
echo "melk: Install JDK (OpenJDK 17)"
if ! pacman -Qq jdk17-openjdk &>/dev/null; then
  sudo pacman -Syu --noconfirm jdk17-openjdk || { echo "Failed to install JDK 17"; exit 1; }
else
  echo "JDK 17 already installed"
fi

# adb/fastboot (fallback even if SDK has platform-tools)
echo "melk: Install android-tools (adb/fastboot)"
if ! pacman -Qq android-tools &>/dev/null; then
  sudo pacman -S --noconfirm android-tools || { echo "Failed to install android-tools"; exit 1; }
else
  echo "android-tools already installed"
fi

# Cmdline tools (sdkmanager/avdmanager) from AUR
echo "melk: Install Android SDK cmdline tools (AUR)"
if ! yay -Qq android-sdk-cmdline-tools-latest &>/dev/null; then
  yay -Sy --noconfirm android-sdk-cmdline-tools-latest || { echo "Failed to install cmdline-tools"; exit 1; }
else
  echo "cmdline-tools already installed"
fi

# Optional emulator package (not strictly required if Studio installed it)
if ! yay -Qq android-emulator &>/dev/null; then
  echo "melk: Install Android Emulator (AUR)"
  yay -Sy --noconfirm android-emulator || echo "android-emulator AUR install skipped/failed (will rely on Studio SDK)"
else
  echo "android-emulator already installed"
fi

# Resolve ANDROID_SDK_ROOT
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_SDK_ROOT_DEFAULT}"
if [ ! -d "$ANDROID_SDK_ROOT" ]; then
  mkdir -p "$ANDROID_SDK_ROOT"
fi

# Prefer cmdline-tools from AUR location if present (idempotent linking)
AUR_SDK="/opt/android-sdk"
if [ -d "$AUR_SDK/cmdline-tools/latest/bin" ] && [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]; then
  echo "Linking cmdline-tools from $AUR_SDK into $ANDROID_SDK_ROOT"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  ln -sfn "$AUR_SDK/cmdline-tools/latest" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
elif [ -L "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]; then
  echo "cmdline-tools symlink already exists"
elif [ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]; then
  echo "cmdline-tools already available in $ANDROID_SDK_ROOT"
fi

# Set env vars for this run
export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"
if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" ]; then
  export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/tools/bin:$PATH"
else
  # Fallback to AUR location
  export PATH="$AUR_SDK/platform-tools:$AUR_SDK/emulator:$AUR_SDK/cmdline-tools/latest/bin:$AUR_SDK/tools:$AUR_SDK/tools/bin:$PATH:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator"
fi

# Function to safely add/update environment variable in .bashrc
update_bashrc_var() {
  local var_name="$1"
  local var_value="$2"
  local brc="$HOME/.bashrc"

  # Create .bashrc if it doesn't exist
  touch "$brc"

  # Check if variable is already exported in .bashrc
  if grep -q "^export ${var_name}=" "$brc" 2>/dev/null; then
    # Variable exists, check if value matches
    local current_value=$(grep "^export ${var_name}=" "$brc" | head -1 | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/')
    if [ "$current_value" != "$var_value" ]; then
      echo "Updating $var_name in $brc (was: $current_value)"
      # Use sed to replace the first occurrence
      sed -i "0,/^export ${var_name}=.*/{s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|}" "$brc"
    else
      echo "$var_name already correctly set in $brc"
    fi
  elif grep -q "^${var_name}=" "$brc" 2>/dev/null; then
    # Variable exists but not exported, convert to export
    echo "Converting $var_name to export in $brc"
    sed -i "s|^${var_name}=|export ${var_name}=|" "$brc"
  else
    # Variable doesn't exist, add it
    echo "Adding $var_name to $brc"
    echo "export ${var_name}=\"${var_value}\"" >> "$brc"
  fi
}

# Function to safely update PATH in .bashrc
update_bashrc_path() {
  local new_paths="$1"
  local brc="$HOME/.bashrc"
  local marker="# Android SDK paths (omarchy)"

  # Create .bashrc if it doesn't exist
  touch "$brc"

  # Check if our marker exists
  if grep -q "$marker" "$brc" 2>/dev/null; then
    # Update existing PATH modification
    echo "Updating Android SDK PATH in $brc"
    # Remove old Android SDK PATH line and add new one
    sed -i "/$marker/,+1d" "$brc"
    {
      echo "$marker"
      echo "export PATH=\"$new_paths:\$PATH\""
    } >> "$brc"
  else
    # Check if any of our paths are already in PATH modifications
    local has_android_paths=false
    for path_component in $(echo "$new_paths" | tr ':' ' '); do
      if grep -q "PATH.*$path_component" "$brc" 2>/dev/null; then
        has_android_paths=true
        break
      fi
    done

    if [ "$has_android_paths" = "false" ]; then
      echo "Adding Android SDK paths to PATH in $brc"
      {
        echo "$marker"
        echo "export PATH=\"$new_paths:\$PATH\""
      } >> "$brc"
    else
      echo "Some Android SDK paths already present in PATH in $brc"
    fi
  fi
}

# Persist environment variables to ~/.bashrc with sophisticated handling
echo "Configuring Android SDK environment variables in ~/.bashrc"

# Update individual variables
update_bashrc_var "ANDROID_SDK_ROOT" "$ANDROID_SDK_ROOT_DEFAULT"
update_bashrc_var "ANDROID_HOME" "\$ANDROID_SDK_ROOT"

# Update PATH with Android SDK components
ANDROID_PATHS="\$ANDROID_SDK_ROOT/platform-tools:\$ANDROID_SDK_ROOT/emulator:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/tools:\$ANDROID_SDK_ROOT/tools/bin"
update_bashrc_path "$ANDROID_PATHS"

# JAVA_HOME (prefer JDK 17) and persist to ~/.bashrc if needed
if [ -d /usr/lib/jvm/java-17-openjdk ]; then
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
  update_bashrc_var "JAVA_HOME" "/usr/lib/jvm/java-17-openjdk"
elif [ -d /usr/lib/jvm/java-21-openjdk ]; then
  export JAVA_HOME="/usr/lib/jvm/java-21-openjdk"
  update_bashrc_var "JAVA_HOME" "/usr/lib/jvm/java-21-openjdk"
fi

# Accept licenses (non-interactive) - multiple approaches for robustness
if command -v sdkmanager &>/dev/null; then
  echo "Accepting Android SDK licenses..."

  # Method 1: Use --sdk_root to ensure we're using the right SDK location
  SDKMANAGER_OPTS="--sdk_root=$ANDROID_SDK_ROOT"

  # Method 2: Try multiple license acceptance approaches
  {
    # First try with explicit yes responses for common licenses
    printf 'y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n' | sdkmanager $SDKMANAGER_OPTS --licenses 2>/dev/null
  } || {
    # Fallback: unlimited yes stream
    yes | timeout 30 sdkmanager $SDKMANAGER_OPTS --licenses 2>/dev/null
  } || {
    # Last resort: try without sdk_root option
    yes | timeout 30 sdkmanager --licenses 2>/dev/null
  } || {
    echo "License acceptance may have failed, but continuing..."
  }

  echo "License acceptance completed"
else
  echo "WARNING: sdkmanager not found on PATH; cmdline-tools may not be linked correctly."
fi

# Install core SDK components (check if already installed)
if command -v sdkmanager &>/dev/null; then
  echo "Checking/Installing SDK components via sdkmanager..."

  # Check each component individually and only install if missing
  for component in "platform-tools" "emulator" "$PLATFORM" "$BUILD_TOOLS" "$SYS_IMAGE"; do
    if ! sdkmanager $SDKMANAGER_OPTS --list_installed 2>/dev/null | grep -q "^${component}"; then
      echo "Installing missing component: $component"
      # Auto-accept licenses during installation
      yes | sdkmanager $SDKMANAGER_OPTS --install "$component" 2>/dev/null || {
        echo "Failed to install $component"; exit 1;
      }
    else
      echo "Component already installed: $component"
    fi
  done
else
  echo "Skipping sdkmanager installs (not found)."
fi

# Create AVD if missing
if command -v avdmanager &>/dev/null; then
  # First ensure we have the AVD directory
  mkdir -p "$HOME/.android/avd" 2>/dev/null || true
  mkdir -p "$ANDROID_SDK_ROOT/avd" 2>/dev/null || true

  if ! "$ANDROID_SDK_ROOT/emulator/emulator" -list-avds 2>/dev/null | grep -qx "$AVD_NAME"; then
    echo "Creating AVD: $AVD_NAME"

    # First, let's check what system images are available
    echo "Available system images:"
    sdkmanager $SDKMANAGER_OPTS --list 2>/dev/null | grep "system-images" | head -10

    # Try to find a suitable system image from installed packages
    AVAILABLE_IMAGE=$(sdkmanager $SDKMANAGER_OPTS --list_installed 2>/dev/null | grep "system-images;android-34" | grep -E "(google_apis|default)" | head -1 | awk '{print $1}')

    if [ -n "$AVAILABLE_IMAGE" ]; then
      echo "Using installed system image: $AVAILABLE_IMAGE"
      echo "Debug: ANDROID_SDK_ROOT = $ANDROID_SDK_ROOT"
      echo "Debug: avdmanager path = $(which avdmanager)"

      # Try different approaches to create AVD
      echo "no" | ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" avdmanager create avd -n "$AVD_NAME" -k "$AVAILABLE_IMAGE" || {
        echo "Retrying with --force flag..."
        echo "no" | ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" avdmanager create avd -n "$AVD_NAME" -k "$AVAILABLE_IMAGE" --force || {
          echo "Retrying without device specification..."
          echo "no" | ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" avdmanager create avd -n "$AVD_NAME" -k "$AVAILABLE_IMAGE" --force --tag google_apis || {
            echo "Failed to create AVD $AVD_NAME with image $AVAILABLE_IMAGE"
            echo "Debug: Checking system image directory structure..."
            echo "Looking for: $ANDROID_SDK_ROOT/system-images/android-34/"
            ls -la "$ANDROID_SDK_ROOT/system-images/" 2>/dev/null || echo "system-images directory not found"
            echo ""
            echo "Contents of android-34 directory:"
            ls -la "$ANDROID_SDK_ROOT/system-images/android-34/" 2>/dev/null || echo "android-34 directory not found"
            echo ""
            echo "Contents of google_apis subdirectory:"
            ls -la "$ANDROID_SDK_ROOT/system-images/android-34/google_apis/" 2>/dev/null || echo "google_apis directory not found"
            echo ""
            echo "Contents of x86_64 subdirectory:"
            ls -la "$ANDROID_SDK_ROOT/system-images/android-34/google_apis/x86_64/" 2>/dev/null || echo "x86_64 directory not found"
            echo ""
            echo "Checking what avdmanager can see:"
            ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" avdmanager list target 2>/dev/null || echo "Failed to list targets"
            echo ""
            echo "Final attempt: trying to create AVD with simpler parameters..."
            echo "no" | ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" avdmanager create avd -n "$AVD_NAME" -k "$AVAILABLE_IMAGE" -p "$ANDROID_SDK_ROOT/avd/$AVD_NAME.avd" --force || {
              echo "All AVD creation attempts failed. AVD creation will be skipped."
              echo "You can manually create an AVD later using Android Studio or the command line."

            }
          }
        }
      }
    else
      echo "No suitable Android 34 system image found in installed packages. Trying with any available API level..."
      FALLBACK_IMAGE=$(sdkmanager $SDKMANAGER_OPTS --list_installed 2>/dev/null | grep "system-images" | grep -E "(google_apis|default)" | head -1 | awk '{print $1}')

      if [ -n "$FALLBACK_IMAGE" ]; then
        echo "Using fallback system image: $FALLBACK_IMAGE"
        echo "no" | ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" avdmanager create avd -n "$AVD_NAME" -k "$FALLBACK_IMAGE" --force || {
          echo "Failed to create AVD $AVD_NAME with fallback image $FALLBACK_IMAGE"
          echo "AVD creation will be skipped - you can create it manually later.";
        }
      else
        echo "No system images available for AVD creation. Skipping AVD creation."
      fi
    fi
  else
    echo "AVD $AVD_NAME already exists"
  fi
else
  echo "Skipping AVD creation (avdmanager not found)."
fi

# Ensure repo wrapper is executable if present (won't affect Windows)
if [ -f "./bin/adb" ]; then
  chmod +x "./bin/adb" || true
fi

# Optional: start emulator (check if already running)
if [ "$START_EMULATOR" = "true" ] && [ -x "$ANDROID_SDK_ROOT/emulator/emulator" ]; then
  # Check if emulator is already running
  if ! adb devices 2>/dev/null | grep -q "emulator"; then
    echo "Starting emulator: $AVD_NAME"
    nohup "$ANDROID_SDK_ROOT/emulator/emulator" -avd "$AVD_NAME" -netdelay none -netspeed full >/dev/null 2>&1 &
    sleep 5
  else
    echo "Emulator already running"
  fi
fi

# Final checks
echo "melk: Final checks"
echo "ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT"
echo "Using adb: $(command -v adb || echo 'not found')"
adb version 2>/dev/null | sed -n '1,3p' || true
echo "Available AVDs:"
"$ANDROID_SDK_ROOT/emulator/emulator" -list-avds 2>/dev/null || true

echo "✓ Android setup complete"
echo "Tip: open a new shell or run: source ~/.bashrc"
echo "✓ Migration complete"
