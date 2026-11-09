# Note Pad

A simple addon for **WoW Forever** to take notes. It opens a window with tabs, one note per tab. Whatever you type is saved, and all your characters on the account see the same notes.

Version 0.0.2 (beta). This is a test version and has not been fully tested in the game yet. Please report any problems you find in a [GitHub issue](https://github.com/gettic/NotePad/issues).

- [Install](#install)
- [Open and close](#open-and-close)
- [Writing notes](#writing-notes)
- [Tabs](#tabs)
- [Moving, resizing and minimizing](#moving-resizing-and-minimizing)
- [Minimap button](#minimap-button)
- [Slash commands](#slash-commands)
- [For developers](#for-developers)

## Install

1. Download the zip from the [latest release](https://github.com/gettic/NotePad/releases) (betas are marked "Pre-release").
2. Unzip the `NotePad` folder into your game's `Interface\AddOns\` folder, so you have `Interface\AddOns\NotePad\NotePad_Forever.toc`.
3. Restart the game, or type `/reload` if it was already running.

## Open and close

| How | What it does |
|---|---|
| `/np` or `/notepad` | Opens or closes the window |
| Minimap button | Click to open or close |
| The minimap's addon menu | Click Note Pad to open or close |
| The X at the top right | Closes the window |
| Esc | Closes the window (when you are not typing) |

The window starts closed when you log in. It also works in combat.

## Writing notes

- Click into the text box to type. Clicking the empty space below your text puts the cursor at the end.
- Enter starts a new line. There is no length limit. Long notes scroll.
- Your notes are saved as you type, so `/reload` or logging out never loses them.
- Opening the window doesn't start typing, so your movement keys still work until you click into the text.
- Esc while typing stops typing. Press Esc again to close the window.

## Tabs

Each note has its own tab.

| Action | What it does |
|---|---|
| Click a tab | Shows that note |
| Red `[+]` button | Adds a new note (up to 20) |
| Double-click a tab | Renames the note |
| Right-click a tab | Menu: Rename, Move left, Move right, Delete |

- Deleting a note always asks "Are you sure?" first, also when the note is empty.
- The last note can't be deleted.
- If you used version 0.0.1, your old note is now the first tab. Nothing is lost.

## Moving, resizing and minimizing

- Drag the window by its title bar or edge to move it.
- Drag the corner at the bottom right to change its size (from 260 x 180 up to 1200 x 900).
- The minimize button, next to the X, folds the window down to a clean dark title bar. Click it again to unfold.
- The window's place, size and folded state are remembered, also after `/reload`.
- `/np reset` puts the window back in the middle of the screen at its normal size, and unfolds it.

## Minimap button

- Click: opens or closes the window.
- Drag: moves the button around the minimap. Its place is remembered.
- `/np minimap` hides the button. Type it again to show it.

## Slash commands

Type `/np` or `/notepad`, followed by:

| Command | What it does |
|---|---|
| (nothing) | Opens or closes the window |
| `reset` | Moves the window back to the middle, to its normal size, and unfolds it |
| `minimap` | Hides or shows the minimap button |
| `help` | Lists the commands |

## For developers

The addon lives in `NotePad\`. It uses no libraries and only the game's own pictures. Files load in this order (see `NotePad_Forever.toc`):

| File | Job |
|---|---|
| `Core.lua` | Saved data, start-up and the slash commands |
| `Window.lua` | The window, the text box, moving, resizing and minimizing |
| `Tabs.lua` | The tab row: add, switch, rename, move and delete notes |
| `Minimap.lua` | The minimap button |

Saved data is in `NotePadDB` (one for the whole account): the notes (title and text each), which one is open, the window's place, size and folded state, and the minimap button's place and whether it is hidden.

## Licence

All rights reserved. See [LICENSE](LICENSE).
