#!/usr/bin/env bash
# Builds the release APK and names it after the pubspec version,
# e.g. build/app/outputs/flutter-apk/moneylens-1.0.3+4.apk.
#
# The Web Client ID comes from dart_defines.json (gitignored), see
# docs/setup-google-cloud.md, section 4.
set -euo pipefail

cd "$(dirname "$0")/.."

defines=dart_defines.json
if [[ ! -f $defines ]]; then
  echo "Missing app/$defines. Create it with:" >&2
  echo '  {"GOOGLE_SERVER_CLIENT_ID": "<web-client-id>.apps.googleusercontent.com"}' >&2
  exit 1
fi

version=$(sed -n 's/^version: *//p' pubspec.yaml)
if [[ -z $version ]]; then
  echo "No version: line in pubspec.yaml" >&2
  exit 1
fi

flutter build apk --release --dart-define-from-file="$defines"

out=build/app/outputs/flutter-apk
cp "$out/app-release.apk" "$out/moneylens-$version.apk"
echo "APK: $PWD/$out/moneylens-$version.apk"
