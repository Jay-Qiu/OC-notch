#!/bin/bash
# Interactive version selector with arrow keys
# Usage: ./select-version.sh <Info.plist path>
# Outputs: selected version string to stdout
set -euo pipefail

PLIST="${1:?Usage: select-version.sh <Info.plist>}"

CURRENT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"

V_PATCH="$MAJOR.$MINOR.$((PATCH + 1))"
V_MINOR="$MAJOR.$((MINOR + 1)).0"
V_MAJOR="$((MAJOR + 1)).0.0"

LABELS=(
  "patch  →  $V_PATCH   (bug fixes)"
  "minor  →  $V_MINOR   (new features)"
  "major  →  $V_MAJOR   (breaking changes)"
)
VERSIONS=("$V_PATCH" "$V_MINOR" "$V_MAJOR")
COUNT=${#LABELS[@]}
SEL=0

# ─── Draw ────────────────────────────────────────────────────────
draw() {
  for i in "${!LABELS[@]}"; do
    tput el # clear line
    if [ "$i" -eq "$SEL" ]; then
      printf "  \033[1;36m❯ %s\033[0m\n" "${LABELS[$i]}"
    else
      printf "    %s\n" "${LABELS[$i]}"
    fi
  done
}

# ─── Main ────────────────────────────────────────────────────────
echo ""
echo "  Current version: $CURRENT"
echo ""
tput civis # hide cursor
draw

while true; do
  IFS= read -rsn1 key
  case "$key" in
    $'\x1b')
      read -rsn2 rest
      case "$rest" in
        '[A') ((SEL > 0)) && ((SEL--)) ;;          # up
        '[B') ((SEL < COUNT - 1)) && ((SEL++)) ;;   # down
      esac
      ;;
    '') break ;; # enter
  esac
  tput cuu "$COUNT"
  draw
done

tput cnorm # show cursor
echo ""

CHOSEN="${VERSIONS[$SEL]}"
printf "  → Will publish \033[1mv%s\033[0m. Continue? [Y/n] " "$CHOSEN"
read -r CONFIRM
case "${CONFIRM:-y}" in
  y|Y|yes|Yes) ;;
  *) echo "  Aborted."; exit 1 ;;
esac

echo "$CHOSEN"
