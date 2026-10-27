#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_PATH="${1:?Usage: verify_design_apk.sh signed.apk}"
: "${ANDROID_HOME:?Android SDK is required to verify the APK signature}"
EXPECTED_CERT="$(tr -d '[:space:]:' < "$ROOT_DIR/tools/design_android_certificate.sha256" | tr '[:upper:]' '[:lower:]')"
[[ "$EXPECTED_CERT" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Invalid pinned Design signing certificate." >&2
  exit 1
}
CERT_REPORT="$("$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$APK_PATH")"
ACTUAL_CERT="$(printf '%s\n' "$CERT_REPORT" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | tr -d '[:space:]:' | tr '[:upper:]' '[:lower:]')"
if [[ "$ACTUAL_CERT" != "$EXPECTED_CERT" ]] ||
    grep -q '^Signer #2 ' <<< "$CERT_REPORT"; then
  echo "APK is not signed exclusively with the pinned Design certificate." >&2
  exit 1
fi
printf '%s\n' "$CERT_REPORT"
echo "Verified persistent Design signing certificate: $EXPECTED_CERT"
