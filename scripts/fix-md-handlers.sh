#!/usr/bin/env bash
#
# Repair LaunchServices handler preferences that still point at the Debug
# build after its bundle went away.
#
# Running the app from Xcode registers `doc.md-preview.dev` with
# LaunchServices, and opening a Markdown file with it once makes that bundle
# the persisted default handler for `net.daringfireball.markdown` (and other
# Markdown UTIs). The persisted preference lives in
# ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
# and is NOT cleaned up when DerivedData is wiped. Quick Look's
# "appex record for item" resolution follows the persisted layer, so every
# Finder Space-press on a .md file then spins while the lookup dead-ends on
# the missing dev bundle — LSCopyDefaultRoleHandlerForContentType happily
# falls back at the same time, which is why the breakage is so confusing.
#
# This script repoints those entries at the installed release bundle
# (`doc.md-preview`) and restarts lsd so the change sticks.
#
# Usage:
#   scripts/fix-md-handlers.sh             Fix entries (backs up the plist first)
#   scripts/fix-md-handlers.sh --dry-run   Only print what would change
#   scripts/fix-md-handlers.sh --check     Exit 1 if dangling entries exist

set -euo pipefail

PLIST="$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
DEV_ID="doc.md-preview.dev"
RELEASE_ID="doc.md-preview"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

MODE="fix"
case "${1:-}" in
    --dry-run) MODE="dry-run" ;;
    --check)   MODE="check" ;;
    "")        ;;
    *) echo "usage: $0 [--dry-run|--check]" >&2; exit 2 ;;
esac

if [[ ! -f "$PLIST" ]]; then
    echo "No LaunchServices preference plist at $PLIST — nothing to fix."
    exit 0
fi

# If the dev bundle is actually registered, the election is live, not stale.
if "$LSREGISTER" -dump 2>/dev/null | grep -q "identifier: *$DEV_ID"; then
    echo "$DEV_ID is currently registered (a Debug build is alive)."
    echo "Nothing to repair — delete/clean that build first if it should stop owning the handler."
    exit 0
fi

ENTRY_COUNT=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers" "$PLIST" 2>/dev/null | grep -c "Dict {" || true)
if [[ "$ENTRY_COUNT" -eq 0 ]]; then
    echo "No LSHandlers entries found — nothing to fix."
    exit 0
fi

MATCHING=()
for ((i = 0; i < ENTRY_COUNT; i++)); do
    role=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSHandlerRoleAll" "$PLIST" 2>/dev/null || true)
    if [[ "$role" == "$DEV_ID" ]]; then
        uti=$(/usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSHandlerContentType" "$PLIST" 2>/dev/null \
              || /usr/libexec/PlistBuddy -c "Print :LSHandlers:$i:LSHandlerURLScheme" "$PLIST" 2>/dev/null \
              || echo "(unnamed)")
        MATCHING+=("$i")
        echo "dangling: [$i] $uti -> $DEV_ID"
    fi
done

if [[ ${#MATCHING[@]} -eq 0 ]]; then
    echo "No handler entries point at $DEV_ID — LaunchServices preferences are healthy."
    exit 0
fi

if [[ "$MODE" == "check" ]]; then
    echo "Found ${#MATCHING[@]} dangling entries — run scripts/fix-md-handlers.sh to repair."
    exit 1
fi

if [[ "$MODE" == "dry-run" ]]; then
    echo "dry-run: would repoint ${#MATCHING[@]} entries to $RELEASE_ID and restart lsd."
    exit 0
fi

BACKUP="/tmp/launchservices.secure.backup.$(date +%Y%m%d%H%M%S).plist"
cp "$PLIST" "$BACKUP"
echo "backup: $BACKUP"

for i in "${MATCHING[@]}"; do
    /usr/libexec/PlistBuddy -c "Set :LSHandlers:$i:LSHandlerRoleAll $RELEASE_ID" "$PLIST"
done

killall lsd 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo "Repaired ${#MATCHING[@]} entries: $DEV_ID -> $RELEASE_ID (lsd restarted, Quick Look cache reset)."
