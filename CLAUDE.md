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

## Release path (Founder ruling 2026-09-09)

Build → Assure → **unpublished release candidate** → Founder Test → **Founder GO** → public release.
A session may build (`tools/make-release.sh`), run the headless suite, commit and push, and prepare
a **draft** GitHub release or an unpublished asset. Anything the public can see — publishing a
release, the addons.videolan.org listing, a forum or social post, flipping repository visibility,
a rename of the public name — happens only on the Founder's explicit GO, recorded as an annotated
tag `founder-go/<short sha>` on origin (`git tag -a founder-go/<sha> -m 'Founder GO <date> ·
<ACE-OpenSource-FolderWatch-nnnn> · "<quoted GO>"'`), created only after the GO is given. The
Founder's review of every public text before it goes out is a standing ruling (2026-09-06); the
review pack that recorded it is local and untracked, so this section is the tracked statement of
the rule.
