# Notebook

A small notes addon for World of Warcraft Forever, modeled on the iOS Notes app. Each note has a **subject** and a **body**. The list window shows just the subjects, and clicking one opens a lightweight editor window.

Notes can be **account-wide** (shared by every character) or **character-only**. A checkbox on each note moves it between the two.

## Features

- List window showing note subjects, with a search box that filters by subject. New notes appear at the top; drag a subject to rearrange the list (while the window is unlocked and the search is empty). Character-only notes carry a small `char` tag.
- Note window with an editable subject, an editable multi-line body, a "Character only" checkbox and a Delete button (with confirmation). Changes save as you type.
- Notes that are closed while completely empty are discarded.
- A "Sticky" checkbox in the note window makes that note ignore Escape and stay open when you close the list. If a sticky note was open, it reopens on that character after a `/reload` or relog.
- Shift-click items, quests and other links into the subject or body while you are typing in it. The field then leaves edit mode so the links show their full tooltip on hover and respond to clicks (for example Ctrl-click to preview an item); click the text to keep editing.
- The list and note windows are resizable (drag the bottom-right corner). Each character remembers its own window positions and sizes.
- A lock button next to the list window's title locks its position, size and note order (per character), and a Settings button next to New opens the settings window.
- Optional "open window on login" shows the notes list when you log in (a `/reload` instead restores whether the list was open), handy for leaving yourself a "what I was doing last time" note. The only other thing that reopens automatically is a sticky note that was open.
- Settings window (all settings persist across reloads and relogs):
  - Character specific settings (checkbox on the title line): off, settings are shared by all characters; on, changes you make are saved for this character only. Anything you haven't changed for the character still follows the account-wide value.
  - New notes are character-only (default scope for new notes)
  - Open window on login
  - Notes list layer (frame strata), so the list can sit over more or fewer other UI elements
  - Per window (notes list and note window, independently):
    - Show border (off gives a flat dark background)
    - Opacity, 0% to 100%, via buttons or a slider. Backgrounds, borders, text boxes and scroll bars fade; text and buttons stay visible, so the list can float in a corner.
  - Which side of the list window the note window opens on: right, left, above or below

The note window is a separate window: drag it anywhere and it remembers that spot. Changing the "opens on" side clears the remembered spot so the note opens beside the list again.

The note window is always on the High layer and the settings window on Dialog, so neither can get lost behind other UI. The settings window also ignores the border and opacity settings.

## Installation

1. Copy the `Notebook` folder (containing `Notebook.toc` and `Notebook.lua`) into your client's AddOns directory, e.g. `World of Warcraft/_forever_/Interface/AddOns/`.
2. Start the game, or run `/reload` if it is already running.

`Notebook.toc` declares `## Interface: 16001`, which is the interface version reported for the Forever client. If the addon shows up as out of date, update that number to match your client.

## Usage

| Command | Action |
| --- | --- |
| `/nb` or `/nb toggle` | Toggle the notes list (`/notebook` works the same) |
| `/nb settings` (also `config`, `options`) | Toggle the settings window |
| `/nb lock` / `/nb unlock` | Lock or unlock the list window's position, size and note order |
| `/nb debug` | Toggle debug output for shift-click link insertion (for troubleshooting) |
| `/nb help` | List the available commands (also shown for any unrecognized command) |

The list window does not close on Escape, so it can stay on screen. The note and settings windows do close on Escape. Use the list window's close button or `/nb` to hide the list.

## Saved data

- `NotebookDB` (account-wide): account notes and the account-wide settings.
- `NotebookCharDB` (per character): character-only notes, window positions and sizes, and this character's setting overrides when "Character specific settings" is on.

See `AGENTS.md` for the data layout and development notes.

## License

MIT. See `LICENSE`.
