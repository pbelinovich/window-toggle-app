#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Window Toggle.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
swiftc "$ROOT/main.swift" -o "$APP/Contents/MacOS/WindowToggle" -framework AppKit -framework ApplicationServices
codesign --force --sign - --identifier local.windowtoggle \
  --requirements '=designated => identifier "local.windowtoggle"' "$APP"
printf 'Built: %s\n' "$APP"
