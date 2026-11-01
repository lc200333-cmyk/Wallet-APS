#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
DIST_DIR="$ROOT_DIR/dist"
BUILD_MODE="${BUILD_MODE:-debug}"

if [ "$BUILD_MODE" != "debug" ] && [ "$BUILD_MODE" != "release" ]; then
  echo "BUILD_MODE должен быть debug или release." >&2
  exit 1
fi

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK не найден. Установите Flutter stable и добавьте flutter в PATH." >&2
  exit 1
}

mkdir -p "$DIST_DIR"
cd "$APP_DIR"

if [ ! -f "android/app/build.gradle.kts" ]; then
  flutter create --platforms=android .
fi
sed -i 's/compileSdk = flutter\.compileSdkVersion/compileSdk = 36/' android/app/build.gradle.kts
if ! grep -q 'plugins.withId("com.android.library")' android/build.gradle.kts; then
  cat >> android/build.gradle.kts <<'GRADLE'

subprojects {
    fun forceCompileSdk36() {
        extensions.findByName("android")?.let { androidExtension ->
            androidExtension.javaClass.methods
                .firstOrNull { method ->
                    method.name == "setCompileSdk" && method.parameterTypes.size == 1
                }
                ?.invoke(androidExtension, 36)
        }
    }
    plugins.withId("com.android.application") {
        forceCompileSdk36()
    }
    plugins.withId("com.android.library") {
        forceCompileSdk36()
    }
}
GRADLE
fi

patch_plugin_compile_sdk() {
  local plugin_name="$1"
  local pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"

  [ -d "$pub_cache" ] || return 0

  while IFS= read -r -d '' gradle_file; do
    sed -i \
      -e 's/compileSdkVersion[[:space:]]*flutter\.compileSdkVersion/compileSdkVersion 36/g' \
      -e 's/compileSdk[[:space:]]*=[[:space:]]*flutter\.compileSdkVersion/compileSdk = 36/g' \
      -e 's/compileSdk[[:space:]]*flutter\.compileSdkVersion/compileSdk 36/g' \
      -e 's/compileSdkVersion[[:space:]]*[0-9][0-9]*/compileSdkVersion 36/g' \
      -e 's/compileSdk[[:space:]]*=[[:space:]]*[0-9][0-9]*/compileSdk = 36/g' \
      -e 's/compileSdk[[:space:]]*[0-9][0-9]*/compileSdk 36/g' \
      "$gradle_file"
  done < <(
    find "$pub_cache" -type f \
      \( -path "*/$plugin_name-*/android/build.gradle" -o -path "*/$plugin_name-*/android/build.gradle.kts" \) \
      -print0
  )
}

flutter pub get
patch_plugin_compile_sdk file_picker
patch_plugin_compile_sdk flutter_plugin_android_lifecycle
patch_plugin_compile_sdk sqlite3_flutter_libs
patch_plugin_compile_sdk jni
patch_plugin_compile_sdk jni_flutter
"$ROOT_DIR/tools/apply_branding.sh"
flutter build apk "--$BUILD_MODE"

cp "$APP_DIR/build/app/outputs/flutter-apk/app-$BUILD_MODE.apk" "$DIST_DIR/Wallet-APS-android-$BUILD_MODE.apk"
if [ "$BUILD_MODE" = "release" ]; then
  cp "$DIST_DIR/Wallet-APS-android-release.apk" "$DIST_DIR/Wallet-APS-android.apk"
fi
echo "APK готов: $DIST_DIR/Wallet-APS-android-$BUILD_MODE.apk"
