#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/NotchNook.app"
if [ -e "$APP" ]; then
  printf 'Already installed: %s\nQuit the app and move this existing copy to Trash before reinstalling.\n' "$APP"
  exit 1
fi
mkdir -p "$HOME/Applications"
ditto -x -k NotchNook.zip "$HOME/Applications"
codesign --verify --deep --strict "$APP"
open -g "$APP"
