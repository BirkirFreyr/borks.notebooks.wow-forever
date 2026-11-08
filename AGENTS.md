# AGENTS.md

Guidance for AI agents and contributors working on this addon.

## Overview

Notebook is a single-file WoW addon (Lua, no libraries) for the World of Warcraft Forever client (modern client API, `## Interface: 16001`). See `README.md` for the user-facing feature list.

## Layout

- `Notebook.toc` - addon manifest. Declares the interface version and the saved variables.
- `Notebook.lua` - all code. Rough order: style constants and helpers, position helpers, data helpers, note window, list window, settings window, init and slash commands.
- `README.md` - user documentation.
- `AGENTS.md` - this file.

## Saved variables

`NotebookDB` (account-wide):

```
notes     { [id] = { id, subject, text, modified, order, sticky } }   -- account-wide notes; the list is sorted by `order`, rearranged by drag-and-drop
settings  { ... }   -- account-wide settings, see below
pos       -- legacy account-wide window positions; only used to seed a character's first `pos`
```

Settings keys (defaults in `SETTING_DEFAULTS`):

```
defaultCharacterOnly      boolean   -- new notes start as character-only
openOnLogin               boolean   -- show the list window at login
listBorder, noteBorder    boolean   -- dialog border vs flat background, per window
listOpacity, noteOpacity  number    -- 0..1, background/border/scrollbar alpha, per window
noteSide                  string    -- RIGHT | LEFT | ABOVE | BELOW: default side of the list for the note window
strata                    string    -- frame strata of the list window only
```

`NotebookCharDB` (per character):

```
notes             -- character-only notes, same shape as above
settings          -- this character's setting overrides (same keys)
useCharSettings   boolean   -- "Character specific settings" checkbox
pos               { main = {point, relPoint, x, y}, note = {...} }   -- window positions, always per character
size              { main = {w, h}, note = {w, h} }                    -- window sizes, always per character
listLocked        boolean   -- list window position/size locked (lock button)
stickyOpen        id|nil    -- sticky note that was open; reopened at login/reload
listOpen          boolean   -- list window was open; restored on /reload only
```

Settings layering: the game keeps `NotebookDB` and `NotebookCharDB` as separate tables and does not merge them. On load, `CDB.settings` gets a metatable with `__index = DB.settings`, so any key not overridden for the character falls through to the account value. `S` is the active table (`CDB.settings` when `useCharSettings` is set, else `DB.settings`). Always read and write settings through `S`, never directly on `DB`.

A note lives in exactly one of the two stores. Toggling "Character only" moves it between them.

New settings need an entry in `SETTING_DEFAULTS` (and `SETTING_KEYS` follows from it). Never assume a key exists in existing users' saved data.

## Conventions and compatibility

- Match the existing style: 4-space indent, short comments that explain why, `local` functions, and `Notebook_`-prefixed globals only where a forward reference is needed.
- Create frames through `NewFrame`, which adds `BackdropTemplate` on clients that need it. Do not call `SetBackdrop` on frames created any other way.
- All windows get their layer, border and opacity through `ApplyStyle`. A window's `styleKey` (`"list"` or `"note"`) picks its `<key>Border` / `<key>Opacity` settings. If a new window or widget should follow those settings, register it there (see `inputBgs` and `scrollFrames`), and call `ApplyAllStyles` when a setting changes.
- The settings window deliberately has no `styleKey` (always bordered, fully opaque) and a fixed strata (`fixedStrata`, Dialog) so it stays reachable. Keep it that way. The note window also has a fixed strata (High), so only the list follows the `strata` setting.
- The note window opens at its saved (dragged) position if there is one, otherwise beside the list window per `noteSide` (`PlaceNote`). Changing `noteSide` clears the saved note position.
- Older saved data kept settings directly on `NotebookDB`; the `ADDON_LOADED` handler moves any key listed in `SETTING_KEYS` into `DB.settings`. Keep migrations like this when moving or renaming saved data.
- Script handlers take `self` as their first argument. Do not use the legacy `this` globals.
- Prefer widgets that are unlikely to have been removed or changed: plain buttons, checkboxes and hand-built sliders. Avoid `UIDropDownMenu` and other deprecated templates.
- The list and note windows are resizable through `MakeResizable` (bottom-right grip, size saved in `CDB.size`). Keep layouts anchored to the frame edges so they adapt, and keep controls clear of the grip corner.
- Open windows are deliberately not restored on reload or login. The only automatic opens are: on a real login, the list window when `openOnLogin` is set; on `/reload`, the list if it was open (`CDB.listOpen`); and a sticky note that was open (`CDB.stickyOpen`), on both. The handler uses `PLAYER_ENTERING_WORLD` (`isInitialLogin` / `isReloadingUi`) to tell login from reload. A sticky note ignores Escape, which is done by adding/removing the note window in `UISpecialFrames` (`UpdateEscapeClose`), and stays open when the list is closed.
- The list window is intentionally not in `UISpecialFrames`, so Escape does not close it. The note and settings windows are.
- Links: `InsertIntoNote` wraps `ChatEdit_InsertLink` (and `ChatFrameUtil.InsertLink` where it exists) and returns true when it inserted, so bag stacks don't also open the split dialog. EditBoxes can't show hyperlink tooltips, so a field containing a link (`|H`) is shown through a read-only SimpleHTML "view" (`MakeView`) while it isn't focused, and inserting a link clears focus so the view appears right away. Anything that reads note text must use the EditBox text (`GetText`), not the view. Use `PlainText` when matching text against what the user sees.
- `/nb debug` toggles `debugLinks`, which prints what the link-insert hook receives and whether the link views switched on. Keep it around for troubleshooting link behavior.
- Note order: `order` is shared by both stores and the list sorts on it (ties by `modified`). Dropping a note reindexes `order` 1..n for the whole list. Editing or changing a note's scope does not move it. Reordering is disabled while the list is locked or searched.
- Saving is immediate: edits write to the saved variables on every text change.

## Verifying changes

There is no test suite. At minimum, check the syntax of the Lua file (note: LuaJIT is more permissive than the game's Lua 5.1, which rejects a statement starting with `(` right after a call as ambiguous syntax, so never begin a line with `(`):

```
luajit -bl Notebook.lua > /dev/null
```

Then test in game: copy the addon folder into the client's AddOns directory, `/reload`, and exercise the changed behavior. Useful checks:

- Create, edit, move (account/character) and delete notes.
- `/reload` with the list and a note open, and confirm they come back in place.
- Each setting in `/nb settings` takes effect immediately and survives a reload.
- Look for Lua errors (enable "Display Lua Errors" in the game's interface options).

## Documentation

Keep `README.md` and this file current in the same change as the code. Update the feature list, command table and saved-variable layout whenever they change. Do not put machine-specific paths, usernames or other local details in either file or in the code; everything in this repository is meant to be shared.

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager), driven by `.pkgmeta` and the GitHub workflow in `.github/workflows/release.yml`.

- `.pkgmeta` packages the addon as `Notebook/`, uses `CHANGELOG.md` as the changelog, and leaves out developer files (`AGENTS.md`, `README.md`, `.github`).
- `Notebook.toc` has `## Version: @project-version@`, which the packager replaces with the tag name. In an unpackaged checkout the version therefore shows up literally as `@project-version@`; that is expected.
- One-time setup: create the CurseForge project, put its numeric ID in `Notebook.toc` as `## X-Curse-Project-ID: <id>` (a commented placeholder is there), and add a repository secret named `CF_API_KEY` with a CurseForge API token. `GITHUB_TOKEN` is provided automatically.
- To release: update `CHANGELOG.md` and the version-related docs, then push a tag (for example `v1.0.1`). The workflow uploads the package to CurseForge and creates a GitHub release.
- The packager chooses the CurseForge game version from the `## Interface` number in the TOC. If CurseForge does not map `16001` to the Forever flavor on the first upload, fix the game version on the CurseForge file page, or pass the packager a game version explicitly (see its `-g` option).
- `.github/workflows/check.yml` runs `luac5.1 -p` on every push, which catches syntax that LuaJIT accepts but the game's Lua 5.1 rejects.

Keep `CHANGELOG.md` current as features land.
