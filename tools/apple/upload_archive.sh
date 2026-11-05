#!/usr/bin/env bash
# Sign an Xcode archive and upload it to App Store Connect, retrying because
# Apple's services fail intermittently. A retry can find the build already
# uploaded (by an earlier attempt or a re-run of the job); that counts as done.
#
# Usage: upload_archive.sh ARCHIVE_PATH EXPORT_PATH
# Credentials come only from the environment:
# ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (path to the AuthKey .p8 file).
set -euo pipefail

archive="$1"
export_path="$2"
options="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ExportOptions-upload.plist"
pauses=(${UPLOAD_RETRY_PAUSES:-60 180 300})
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

attempt=1
while true; do
  status=0
  xcodebuild -exportArchive -archivePath "$archive" \
    -exportOptionsPlist "$options" \
    -exportPath "$export_path" -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" 2>&1 | tee "$log" || status=$?
  if [ "$status" -eq 0 ]; then
    exit 0
  fi
  if grep -q -i -E 'redundant binary upload|bundle version must be higher|has already been uploaded' "$log"; then
    echo "This build is already in App Store Connect; nothing more to upload."
    exit 0
  fi
  if [ "$attempt" -gt "${#pauses[@]}" ]; then
    echo "Upload failed after $attempt attempts." >&2
    exit "$status"
  fi
  pause="${pauses[$((attempt - 1))]}"
  echo "Upload attempt $attempt failed with exit code $status; retrying in $pause seconds."
  sleep "$pause"
  attempt=$((attempt + 1))
done
