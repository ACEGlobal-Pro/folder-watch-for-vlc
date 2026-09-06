#!/bin/bash
# Headless integration test: runs VLC with the watcher against a throwaway folder and asserts on its log.
# Never opens a window and never touches the real config (FOLDERWATCH_DIR points at the test dir).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SRC="$HERE/../lua"
VLC=/Applications/VLC.app/Contents/MacOS/VLC
LUA="$HOME/Library/Application Support/org.videolan.vlc/lua"
T="${TMPDIR:-/tmp}/folderwatch-test-$$"; MEDIA="$T/media"; STATE="$T/state"; LOG="$T/vlc.log"
mkdir -p "$MEDIA/Root A/Series One" "$MEDIA/Root A/Series Two" "$MEDIA/Root B" "$STATE" "$LUA/sd" "$LUA/intf"
for f in "Root A/Series One/ep01.mp4" "Root A/Series One/ep02.mp4" "Root A/Series Two/s2e01.mkv" "Root B/movie.mp4" "Root B/notes.txt"; do echo x > "$MEDIA/$f"; done
printf 'interval=2\nroot=%s\nroot=%s\n' "$MEDIA/Root A" "$MEDIA/Root B" > "$STATE/folderwatch.conf"
cp "$SRC/sd/folderwatch.lua" "$LUA/sd/folderwatch.lua"; cp "$SRC/intf/folderwatch.lua" "$LUA/intf/folderwatch.lua"

FOLDERWATCH_DIR="$STATE" "$VLC" --extraintf "" -I luaintf --lua-intf folderwatch -V dummy -A dummy --no-osd --no-media-library -vv > "$LOG" 2>&1 &
PID=$!
pass=0; fail=0
wait_for() { # wait_for <seconds> <pattern>
  for _ in $(seq 1 "$1"); do grep -q -- "$2" "$LOG" && return 0; sleep 1; done; return 1; }
check() { if wait_for "$1" "$2"; then echo "PASS  $3"; pass=$((pass+1)); else echo "FAIL  $3  (no '$2' within $1s)"; fail=$((fail+1)); fi; }
expect_absent() { if grep -q -- "$1" "$LOG"; then echo "FAIL  $2"; fail=$((fail+1)); else echo "PASS  $2"; pass=$((pass+1)); fi; }

check 15 "\[folderwatch sd\] tree built: 2 folders, 4 files" "initial tree: 2 subfolders, 4 files (notes.txt ignored)"
check 10 "\[folderwatch\] watching 2 root(s) every 2s" "watcher started with the test config"
sleep 1; if grep -q "last_scan=" "$STATE/folderwatch.status" 2>/dev/null; then echo "PASS  status file written"; pass=$((pass+1)); else echo "FAIL  status file missing"; fail=$((fail+1)); fi

after_last_rebuild() { awk '/rebuilt sidebar tree/{n=NR} {l[NR]=$0} END{for(i=n;i<=NR;i++)print l[i]}' "$LOG"; }
leaves() { after_last_rebuild | grep -o "tree leaf .*" | sed "s#.*media/##"; }
count_rebuilds() { grep -c "rebuilt sidebar tree" "$LOG"; }

rm "$MEDIA/Root A/Series One/ep02.mp4"
check 8 "rebuilt sidebar tree (1 removed, 0 new/changed)" "deleted file triggers a rebuild"
check 5 "tree built: 2 folders, 3 files" "tree rebuilt with 3 files"
sleep 2; if leaves | grep -q "ep02"; then echo "FAIL  ep02 still in the rebuilt tree"; fail=$((fail+1)); else echo "PASS  ep02 gone from the rebuilt tree"; pass=$((pass+1)); fi
[[ $(count_rebuilds) -eq 1 ]] && { echo "PASS  exactly one rebuild so far"; pass=$((pass+1)); } || { echo "FAIL  expected 1 rebuild, saw $(count_rebuilds)"; fail=$((fail+1)); }

echo y > "$MEDIA/Root B/new.mp4"
check 8 "rebuilt sidebar tree (0 removed, 1 new/changed)" "added file triggers a rebuild"
check 5 "tree leaf .*Root%20B/new.mp4" "rebuilt tree lists the new file"

sleep 3; echo zz > "$MEDIA/Root B/movie.mp4"
check 8 "new/changed: movie.mp4" "replaced file (size changed) detected"
[[ $(count_rebuilds) -ge 3 ]] && { echo "PASS  replacement rebuilt the tree"; pass=$((pass+1)); } || { sleep 4; [[ $(count_rebuilds) -ge 3 ]] && { echo "PASS  replacement rebuilt the tree"; pass=$((pass+1)); } || { echo "FAIL  no rebuild after replacement"; fail=$((fail+1)); }; }

rm -r "$MEDIA/Root A/Series Two"
check 8 "rebuilt sidebar tree (2 removed, 0 new/changed)" "deleted folder (and its file) triggers one rebuild"
check 5 "tree built: 1 folders, 3 files" "tree rebuilt without the folder"

sleep 3; [[ $(count_rebuilds) -eq 4 ]] && { echo "PASS  no spurious rebuilds while idle"; pass=$((pass+1)); } || { echo "FAIL  expected 4 rebuilds, saw $(count_rebuilds)"; fail=$((fail+1)); }

mv "$MEDIA/Root B" "$MEDIA/Root B.off"
check 8 "root became unreadable, leaving its tree as is" "unmounted root is left alone"
sleep 3; [[ $(count_rebuilds) -eq 4 ]] && { echo "PASS  unreadable root caused no rebuild"; pass=$((pass+1)); } || { echo "FAIL  rebuild happened for an unreadable root"; fail=$((fail+1)); }
mv "$MEDIA/Root B.off" "$MEDIA/Root B"
check 8 "rebuilt sidebar tree (0 removed, 1 new/changed)" "root back: tree refilled"

date +%s > "$STATE/folderwatch.rescan"
check 8 "rebuilt sidebar tree (manual rescan)" "rescan trigger file forces a rebuild"

printf 'interval=3\nroot=%s\n' "$MEDIA/Root A" > "$STATE/folderwatch.conf"
check 8 "settings reloaded: 1 root(s), interval 3s" "config edit picked up"
check 8 "rebuilt sidebar tree (settings changed)" "config edit rebuilds"
check 5 "tree built: 1 folders, 1 files from 1 root(s)" "tree now shows only the remaining root"

kill -TERM $PID; for _ in $(seq 1 10); do kill -0 $PID 2>/dev/null || break; sleep 1; done
if kill -0 $PID 2>/dev/null; then echo "FAIL  VLC did not exit within 10s of SIGTERM"; fail=$((fail+1)); kill -9 $PID; else echo "PASS  VLC exited cleanly"; pass=$((pass+1)); fi
if grep -qE "lua (interface|services discovery) error|\[folderwatch\] crashed" "$LOG"; then echo "FAIL  Lua errors in log:"; grep -E "lua (interface|services discovery) error|crashed" "$LOG" | cut -c1-300; fail=$((fail+1)); else echo "PASS  no Lua errors"; pass=$((pass+1)); fi


# ---------------------------------------------------------------- phase 2: rebuild waits while the library plays
LOG2="$T/vlc2.log"; MEDIA2="$T/media2"; STATE2="$T/state2"; mkdir -p "$MEDIA2/Root C" "$STATE2"
say -r 120 -o "$MEDIA2/Root C/voice.aiff" "This is the ACE library playback test. It keeps talking for a while so that the watcher sees a file from the library playing, and must not rebuild the tree until playback has ended." 2>/dev/null || { echo "SKIP  phase 2: 'say' unavailable"; }
echo x > "$MEDIA2/Root C/other.mp4"
printf 'interval=2\nroot=%s\n' "$MEDIA2/Root C" > "$STATE2/folderwatch.conf"
if [[ -f "$MEDIA2/Root C/voice.aiff" ]]; then
  FOLDERWATCH_DIR="$STATE2" "$VLC" --extraintf "" -I luaintf --lua-intf folderwatch -V dummy -A dummy --no-osd --no-media-library -vv --run-time=7 "$MEDIA2/Root C/voice.aiff" > "$LOG2" 2>&1 &
  PID2=$!
  LOG="$LOG2"
  check 15 "tree built: 0 folders, 2 files" "phase 2: tree built"
  check 10 "main input debug: Creating an input for 'voice.aiff'" "phase 2: VLC is playing a library file"
  rm "$MEDIA2/Root C/other.mp4"
  check 8 "rebuild deferred: playing from the library" "phase 2: rebuild deferred while playing"
  expect_absent "rebuilt sidebar tree" "phase 2: no rebuild during playback"
  check 20 "rebuilt sidebar tree (1 removed, 0 new/changed)" "phase 2: rebuild ran once playback ended"
  kill -TERM $PID2 2>/dev/null; wait $PID2 2>/dev/null
fi

# ---------------------------------------------------------------- phase 3: settings panel logic through a stub dialog
LOG3="$T/vlc3.log"; STATE3="$T/state3"; mkdir -p "$STATE3" "$LUA/intf"
printf 'interval=15\nroot=%s\n' "$MEDIA/Root A" > "$STATE3/folderwatch.conf"
printf 'last_scan=2026-01-01 00:00:00\nfiles=3\nfolders=1\nlast_action=test\n' > "$STATE3/folderwatch.status"
printf '%s\n' "$MEDIA/Root A/Series One" > "$STATE3/pick.txt"
cp "$HERE/extension-harness.lua" "$LUA/intf/fwexttest.lua"
FOLDERWATCH_DIR="$STATE3" FOLDERWATCH_PICKER_CMD="cat \"$STATE3/pick.txt\"" EXT_SCRIPT="$SRC/extensions/folderwatch.lua" EXT_NEWROOT="$MEDIA/Root B" "$VLC" --extraintf "" -I luaintf --lua-intf fwexttest -V dummy -A dummy --no-osd --no-media-library -v > "$LOG3" 2>&1
rm -f "$LUA/intf/fwexttest.lua"
LOG="$LOG3"
check 1 "descriptor title=Folder Watch for VLC" "phase 3: extension loads (syntax ok)"
check 1 "list has 1 root(s) after activate" "phase 3: config shown in the list"
check 1 "after add: 2 root(s); message=Added" "phase 3: add folder"
check 1 "duplicate add: message=Already in the list" "phase 3: duplicate rejected"
check 1 "bad add: message=Not a readable folder" "phase 3: bad path rejected"
check 1 "bad interval: message=Interval must be" "phase 3: bad interval rejected"
check 1 "save: message=Saved. The sidebar tree rebuilds within 7 seconds" "phase 3: save"
check 1 "picker add: 2 root(s); message=Added and saved: $MEDIA/Root A/Series One" "phase 3: native picker result added and saved"
check 1 "picker cancel: message=No folder chosen" "phase 3: picker cancel handled"
check 1 "first run: picker opened=true" "phase 3: first run with no folders opens the picker"
grep -q "^interval=7$" "$STATE3/folderwatch.conf" && grep -q "^root=$MEDIA/Root B$" "$STATE3/folderwatch.conf" && { echo "PASS  phase 3: config file has interval 7 and the new root"; pass=$((pass+1)); } || { echo "FAIL  phase 3: config content"; cat "$STATE3/folderwatch.conf"; fail=$((fail+1)); }
check 1 "after remove: 1 root(s)" "phase 3: remove selected"
[[ -s "$STATE3/folderwatch.rescan" ]] && { echo "PASS  phase 3: rescan trigger written"; pass=$((pass+1)); } || { echo "FAIL  phase 3: no rescan trigger"; fail=$((fail+1)); }
check 1 "status: Last scan: 2026-01-01 00:00:00<br/>Files: 3<br/>Folders: 1<br/>Last action: test" "phase 3: status rendered"
check 1 "\[exttest\] done" "phase 3: harness finished without error"
if grep -qE "lua interface error" "$LOG3"; then echo "FAIL  phase 3 Lua errors:"; grep -E "lua interface error" "$LOG3" | cut -c1-300; fail=$((fail+1)); fi

echo; echo "passed=$pass failed=$fail  log: $LOG"
[[ $fail -eq 0 ]]
