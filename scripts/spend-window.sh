#!/usr/bin/env bash
# Open the spend report in whatever terminal this desktop actually has.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD="cd '$DIR' && ./scripts/spend.sh; echo; read -n1 -r -p 'press any key to close…'"
for t in x-terminal-emulator gnome-terminal xfce4-terminal konsole xterm; do
  command -v "$t" >/dev/null || continue
  case "$t" in
    gnome-terminal) exec "$t" -- bash -c "$CMD" ;;
    *)              exec "$t" -e bash -c "$CMD" ;;
  esac
done
zenity --info --title="Spend" --width=600 --text="$(cd "$DIR" && ./scripts/spend.sh 2>&1)"
