#!/usr/bin/env bash
# Installs the versioned release APK on an Android emulator and opens the app.
#
# Boots the AVD first when no emulator is running (default Medium_Phone,
# override with AVD=<name>). Builds the APK with build-apk.sh when it is
# missing for the current pubspec version, or always with --build.
#
#   scripts/install-emulator.sh            # install existing APK
#   scripts/install-emulator.sh --build    # rebuild, then install
#   AVD=Pixel_9 scripts/install-emulator.sh
set -euo pipefail

cd "$(dirname "$0")/.."

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
adb=$sdk/platform-tools/adb
emulator=$sdk/emulator/emulator
avd=${AVD:-Medium_Phone}
package=vn.moneylens.app

if [[ ! -x $adb ]]; then
  echo "adb not found at $adb. Set ANDROID_HOME to your Android SDK." >&2
  exit 1
fi

build=false
case ${1:-} in
  "") ;;
  --build) build=true ;;
  *) echo "Usage: $0 [--build]" >&2; exit 1 ;;
esac

version=$(sed -n 's/^version: *//p' pubspec.yaml)
apk=build/app/outputs/flutter-apk/moneylens-$version.apk
if $build || [[ ! -f $apk ]]; then
  scripts/build-apk.sh
fi

running_emulator() {
  "$adb" devices | awk '$1 ~ /^emulator-/ && $2 == "device" { print $1; exit }'
}

serial=$(running_emulator)
if [[ -z $serial ]]; then
  echo "Booting $avd..."
  "$emulator" -avd "$avd" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 90); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "Emulator exited. Check the AVD name with: $emulator -list-avds" >&2
      exit 1
    fi
    serial=$(running_emulator)
    if [[ -n $serial && $("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]]; then
      break
    fi
    serial=
    sleep 2
  done
  if [[ -z $serial ]]; then
    echo "Emulator did not finish booting within 180s." >&2
    exit 1
  fi
fi

echo "Installing $apk on $serial..."
"$adb" -s "$serial" install -r "$apk"
"$adb" -s "$serial" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "Opened $package on $serial."
