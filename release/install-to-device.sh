#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="io.github.clashharmony.app"
ENTRY_ABILITY="EntryAbility"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_HAP="$SCRIPT_DIR/clash-harmony-v0.1.0-20260708-2318-signed.hap"
HAP="${HAP:-$DEFAULT_HAP}"
HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"
SERIAL="${1:-${SERIAL:-}}"

if [ ! -x "$HDC" ]; then
  HDC_FROM_PATH="$(command -v hdc || true)"
  if [ -n "$HDC_FROM_PATH" ]; then
    HDC="$HDC_FROM_PATH"
  fi
fi

if [ ! -x "$HDC" ]; then
  echo "Cannot find hdc. Set HDC=/path/to/hdc and retry." >&2
  exit 1
fi

if [ ! -f "$HAP" ]; then
  echo "Cannot find HAP: $HAP" >&2
  exit 1
fi

if [ -z "$SERIAL" ]; then
  TARGETS="$("$HDC" list targets | awk 'NF > 0 { print $1 }')"
  TARGET_COUNT="$(printf '%s\n' "$TARGETS" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$TARGET_COUNT" = "1" ]; then
    SERIAL="$TARGETS"
  else
    echo "Please pass a device serial:" >&2
    echo "  $HDC list targets" >&2
    echo "  $0 <device-serial>" >&2
    exit 1
  fi
fi

echo "Installing $HAP"
echo "Target device: $SERIAL"
"$HDC" -t "$SERIAL" shell aa force-stop "$APP_BUNDLE" >/dev/null 2>&1 || true
"$HDC" -t "$SERIAL" install -r "$HAP"
"$HDC" -t "$SERIAL" shell aa start -a "$ENTRY_ABILITY" -b "$APP_BUNDLE"
echo "Done."
