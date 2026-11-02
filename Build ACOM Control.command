#!/bin/bash
# Double-click in Finder to build ACOM Control.app and ACOM-Control.dmg on this Mac.
cd "$(dirname "$0")"
echo "=== ACOM Control: local build ==="
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are needed. An installer window will open —"
  echo "click Install, wait for it to finish, then double-click this file again."
  xcode-select --install
  read -n1 -rp "Press any key to close…"; exit 1
fi
set -e
bash build-app.sh
bash make-dmg.sh
echo
echo "Done. Opening the dist folder — double-click ACOM-Control.dmg and drag the app to Applications."
open dist
read -n1 -rp "Press any key to close this window…"
