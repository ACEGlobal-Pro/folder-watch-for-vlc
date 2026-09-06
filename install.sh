#!/bin/bash
# Folder Watch for VLC — installer for macOS and Linux (VLC 3.0 or newer).
#   ./install.sh              copy the scripts into VLC's user Lua folder; write an empty config if none
#   ./install.sh --configure  additionally switch the watcher on in VLC's preferences (VLC must be closed)
#   ./install.sh --uninstall  remove the scripts; config and preferences are left alone
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/lua"
case "$(uname -s)" in
  Darwin) VLC_USER="$HOME/Library/Application Support/org.videolan.vlc"; VLCRC="$HOME/Library/Preferences/org.videolan.vlc/vlcrc" ;;
  *)      VLC_USER="${XDG_DATA_HOME:-$HOME/.local/share}/vlc"; VLCRC="${XDG_CONFIG_HOME:-$HOME/.config}/vlc/vlcrc" ;;
esac
LUA="$VLC_USER/lua"

vlc_running() { pgrep -x VLC >/dev/null 2>&1 || pgrep -x vlc >/dev/null 2>&1; }

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -f "$LUA/sd/folderwatch.lua" "$LUA/intf/folderwatch.lua" "$LUA/extensions/folderwatch.lua"
  echo "Removed the three scripts. Config kept at: $VLC_USER/folderwatch.conf"
  echo "To stop the watcher, untick 'Lua interpreter' under Preferences › Interface › Main interfaces (or set extraintf= empty in vlcrc)."
  exit 0
fi

mkdir -p "$LUA/sd" "$LUA/intf" "$LUA/extensions"
cp "$SRC/sd/folderwatch.lua" "$LUA/sd/folderwatch.lua"
cp "$SRC/intf/folderwatch.lua" "$LUA/intf/folderwatch.lua"
cp "$SRC/extensions/folderwatch.lua" "$LUA/extensions/folderwatch.lua"
echo "Installed into $LUA/{sd,intf,extensions}/folderwatch.lua"

if [[ ! -f "$VLC_USER/folderwatch.conf" ]]; then
  printf '# Folder Watch for VLC — folders shown in the sidebar. One root= line per folder.\ninterval=15\n' > "$VLC_USER/folderwatch.conf"
  echo "Wrote $VLC_USER/folderwatch.conf (no folders yet — choose them in VLC under View › Folder Watch for VLC)"
else
  echo "Kept existing config: $VLC_USER/folderwatch.conf"
fi

if [[ "${1:-}" == "--configure" ]]; then
  if vlc_running; then
    echo "VLC is running — quit it first, then rerun with --configure (VLC may rewrite its preferences on quit)." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$VLCRC")"; touch "$VLCRC"
  cp "$VLCRC" "$VLCRC.bak-folderwatch"
  python3 - "$VLCRC" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8", errors="surrogateescape").read()
def setopt(s, key, val):
    pat = re.compile(r"^#?%s=.*$" % re.escape(key), re.M)
    line = "%s=%s" % (key, val)
    return pat.sub(line, s, count=1) if pat.search(s) else s.rstrip("\n") + "\n" + line + "\n"
s = setopt(s, "extraintf", "luaintf")
s = setopt(s, "lua-intf", "folderwatch")
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
PY
  echo "Watcher enabled in $VLCRC (backup: vlcrc.bak-folderwatch)."
  echo "Start VLC: the sidebar gains 'Folder Watch'. Choose folders under View › Folder Watch for VLC."
else
  cat <<'MSG'

To switch the watcher on (one time), either rerun:  ./install.sh --configure   (with VLC closed)
or in VLC: Preferences › Show All › Interface › Main interfaces: tick "Lua interpreter";
           then Main interfaces › Lua › "Lua interface" = folderwatch. Save, restart VLC.
MSG
fi
