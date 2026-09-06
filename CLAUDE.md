# Folder Watch for VLC — notes for AI assistants

Authoritative project state lives only in version-controlled files here:
`docs/STATE.md` for where the project stands, Git history for what changed.
Memory or notes held outside this repository are never authoritative.

Folder Watch for VLC keeps a folder tree of the user's media in VLC 3's
sidebar and rebuilds it whenever the folders change on disk. Three Lua
scripts, an installer, a headless test suite.

- Current state, known limits, next work → `docs/STATE.md`
- Why the design rebuilds instead of editing rows → the header of `lua/intf/folderwatch.lua`
- Check before claiming anything works: `./test/run-headless.sh`. It runs the
  real VLC binary headlessly; never open a VLC window from a test.
