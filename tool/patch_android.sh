#!/usr/bin/env bash
# Run after `flutter create` in CI: adds permissions, app name and min SDK.
set -euo pipefail

M=android/app/src/main/AndroidManifest.xml

perms='    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.CAMERA"/>'

if ! grep -q ACCESS_FINE_LOCATION "$M"; then
  PERMS="$perms" perl -0pi -e 's#(\s*<application)#\n$ENV{PERMS}\n$1#' "$M"
fi
perl -pi -e 's/android:label="[^"]*"/android:label="TU Ver 01"/' "$M"

for f in android/app/build.gradle android/app/build.gradle.kts; do
  if [ -f "$f" ]; then
    perl -pi -e 's/minSdk(Version)?\s*=?\s*flutter\.minSdkVersion/minSdk = 23/' "$f"
  fi
done

# Browser tab title
if [ -f web/index.html ]; then
  perl -pi -e 's#<title>[^<]*</title>#<title>TU Ver 01</title>#' web/index.html
fi
if [ -f web/manifest.json ]; then
  perl -pi -e 's/"name": "[^"]*"/"name": "TU Ver 01"/; s/"short_name": "[^"]*"/"short_name": "TU Ver 01"/' web/manifest.json
fi

grep -n "uses-permission\|android:label" "$M" | head -20
grep -rn "minSdk" android/app/build.gradle* || true
