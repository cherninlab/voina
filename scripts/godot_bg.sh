#!/bin/sh
# Run Godot without stealing focus: same arguments, output and exit code as "$GODOT".
# Agents use it for every windowed (non --headless) run, e.g. captures:
#   scripts/godot_bg.sh --path . --script scripts/capture_village.gd -- --host --capture-dir=/abs/dir
# On macOS it injects scripts/godot_nofocus.m (built once per version into ~/Library/Caches/voina), so the
# window never becomes active and stays behind the user's windows. Elsewhere it just runs Godot.
set -e
here=$(cd "$(dirname "$0")" && pwd)
godot=${GODOT:-$(git -C "$here" config playtest.godot 2>/dev/null || echo /Applications/Godot.app/Contents/MacOS/Godot)}
if [ "$(uname)" = Darwin ]; then
	cache="$HOME/Library/Caches/voina"
	lib="$cache/godot-nofocus-$(shasum "$here/godot_nofocus.m" | cut -c1-12).dylib"
	if [ ! -f "$lib" ]; then
		mkdir -p "$cache"
		# Parallel agents may build at once: build privately, then rename atomically.
		clang -dynamiclib -fobjc-arc -framework AppKit -o "$lib.$$" "$here/godot_nofocus.m"
		mv -f "$lib.$$" "$lib"
	fi
	export DYLD_INSERT_LIBRARIES="$lib${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}"
fi
exec "$godot" "$@"
