#!/bin/bash
# Starts the local controller bridge. Double-click this file in Finder, leave the
# Terminal window open while you play, then open the game in any browser.
cd "$(dirname "$0")" || exit 1

if [ ! -x naga-pads ] || [ naga-pads.swift -nt naga-pads ]; then
  echo "Building naga-pads (first run only)..."
  if ! swiftc -O naga-pads.swift -o naga-pads; then
    echo
    echo "Build failed. Install the Xcode command line tools, then run this again:"
    echo "  xcode-select --install"
    read -r -n 1 -p "Press any key to close."
    exit 1
  fi
fi

echo "Controller bridge starting. Keep this window open while you play."
echo "Quit with Ctrl-C."
exec ./naga-pads
