#!/usr/bin/env bash
set -euo pipefail

missing=0
for tool in flutter dart dpkg-deb; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "ok: $tool -> $(command -v "$tool")"
  else
    echo "missing: $tool"
    missing=1
  fi
done

for tool in cmake ninja clang pkg-config; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "ok: $tool -> $(command -v "$tool")"
  else
    echo "missing for linux desktop build: $tool"
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  echo "Не все инструменты установлены. Сборочные скрипты готовы, но артефакты не будут собраны без SDK." >&2
  exit 1
fi
