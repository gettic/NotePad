# Note Pad

A simple addon for **WoW Forever** to take notes. It opens a window with tabs, one note or checklist per tab. Whatever you type is saved, and all your characters on the account see the same notes.

Version 1.0.0-beta.2. Please report any problems you find in a [GitHub issue](https://github.com/gettic/NotePad/issues).

- [Install](#install)
- [Open and close](#open-and-close)
- [Writing notes](#writing-notes)
- [Tabs](#tabs)
- [Checklists](#checklists)
- [Bringing back deleted notes](#bringing-back-deleted-notes)
- [Moving, resizing and folding](#moving-resizing-and-folding)
- [Settings](#settings)
- [Minimap button](#minimap-button)
- [Slash commands](#slash-commands)
- [Self-test](#self-test)
- [For developers](#for-developers)

## Install

1. Download the zip from the [latest release](https://github.com/gettic/NotePad/releases).
2. Unzip the `NotePad` folder into your game's `Interface\AddOns\` folder, so you have `Interface\AddOns\NotePad\NotePad_Forever.toc`.
3. Restart the game, or type `/reload` if it was already running.

## Open and close

| How | What it does |
|---|---|
| `/np` or `/notepad` | Opens or closes the window |
| A key of your choice | Set it in Key Bindings > AddOns > Note Pad > "Open or close Note Pad" |
| Minimap button | Left-click opens or closes the window |
| The minimap's addon menu | Click Note Pad to open or close |
| The X at the top right | Closes the window |
| Esc | Closes the open window (when you are not typing). It leaves the folded bar alone. |

These open the window unfolded. It starts closed when you log in, unless you turn on "Open after login" (see [Settings](#settings)). It also works in combat.

## Writing notes

- Click into the text box to type. Clicking the empty space below your text puts the cursor at the end.
- Enter starts a new line. There is no length limit. Long notes scroll.
- Text notes use the chat font, at the text size you choose (see [Settings](#settings)).
- Your notes are saved as you type, so `/reload` or logging out never loses them.
- Opening the window doesn't start typing, so your movement keys still work until you click into the text.
- Esc while typing stops typing. Press Esc again to close the window.
- Shift-click an item (in your bags, loot or a chat link) while typing to put its link into the note.
- Each note remembers where you were (cursor and scroll) until you log out.

## Tabs

Each note has its own tab.

| Action | What it does |
|---|---|
| Click a tab | Shows that note |
| Red `[+]` button | Adds a new note (up to 20) |
| Shift-click `[+]` | Adds a new checklist |
| Right-click `[+]` | Menu: New note, New checklist, and Bring back (when there is something to bring back) |
| Double-click a tab | Renames the note |
| Right-click a tab | Menu: Rename, Move left, Move right, Turn into checklist (or note), Delete |
| Shift+right-click a tab | Deletes the note (asks first) |
| Hover over a tab | Shows the first line of the note |
| Ctrl+Tab / Ctrl+Shift+Tab | Next / previous note (works while typing) |

- A new note is named after its tab number ("Note 2" for the 2nd tab). If that name is taken, it gets the next free number. New checklists are named "List 2" and so on.
- Names can be up to 24 letters. A tab shows the whole name.
- While renaming, click away to save the new name. Esc cancels.
- When there are more tabs than fit, arrows appear. Click them, or use the mouse wheel on the tab row, to scroll.
- At 20 notes the `[+]` button is greyed out. Delete a note to add another.
- Deleting a note always asks "Delete the note ...?" first, also when the note is empty.
- The last note can't be deleted.
- Notes from version 0.0.1 are kept as the first tab.

## Checklists

A checklist is a tab with lines you can tick off. Make one with Shift-click on `[+]`, the `[+]` right-click menu, or `/np list`.

| Action | What it does |
|---|---|
| Type in the box at the top, press Enter | Adds a line |
| Shift-click an item (bags, loot, chat links) | Adds the item as a line |
| Drag an item from your bags onto the list | Adds the item as a line |
| Click the box in front of a line | Ticks it off, or back on |
| Double-click a line | Edits it (Enter saves, Esc cancels) |
| Right-click a line | Menu: Edit, Move up, Move down, Delete |
| Alt + mouse wheel on a line | Moves the line up or down |
| Shift-click an item line | Puts the item's link into chat |
| "Clear ticked" button | Removes all ticked lines (asks first) |

- Item lines show the item's icon, and hovering shows the item's real tooltip.
- A list can have up to 200 lines.
- A tab's right-click menu turns a note into a checklist and back. If you don't change the list in between, the note comes back with its exact text (blank lines, spacing). If the note has formatting a list can't show, a chat line tells you. Once the list is changed, it comes back as one "[x] " or "[ ] " line per list line.
- Lines can be any length, and long ones can be edited without being cut.
- Older Note Pad versions show a checklist as plain text. Anything typed into it there is kept as a "Recovered note".

## Bringing back deleted notes

`/np undo` brings back the last thing you deleted:

- A deleted note goes back to its old place. The last 3 deleted notes are kept, also after `/reload` or logging out.
- Checklist lines removed with Delete or "Clear ticked" come back too, until you log out.

The same is in the `[+]` right-click menu as "Bring back ...".

## Moving, resizing and folding

- Drag the window by its title bar or edge to move it.
- Drag the corner at the bottom right to change its size (from 260 x 180 up to 1200 x 900).
- The fold button (next to the X) shrinks the window to its title bar. Click it again to unfold.
- You can also fold and unfold by double-clicking the title bar, or by right-clicking the minimap button.
- The window's place, size and folded state are remembered, also after `/reload`.
- `/np reset` puts the window back in the middle of the screen at its normal size, and unfolds it.

## Settings

Click the cog in the title bar (left of the fold button), or right-click the title bar, for this menu:

| Setting | What it does | Command |
|---|---|---|
| Text size | 10 to 18, default 14. Checklist lines are 2 smaller than note text. | `/np size 14` |
| Opacity | 30% to 100%, menu steps 100 to 50. The window is fully visible while the mouse is on it, while you type in it, or while its menu is open. | `/np opacity 80` (`0.5` also means 50%) |
| Lock window | The window can't be moved or resized, and the resize grip hides. Folding and closing still work. | `/np lock` |
| Open after login if it was open | Off by default. If Note Pad was open (or folded) when you logged out, it opens again. Closing it with Esc or X counts as closed. | `/np remember` |
| Reset place and size | Same as `/np reset`. | `/np reset` |

Ctrl + mouse wheel over the text or a checklist also changes the text size. The settings are saved for your whole account.

## Minimap button

- Left-click: opens or closes the window.
- Right-click: folds or unfolds the window. If it is closed, it opens folded.
- Drag: moves the button around the minimap. Its place is remembered.
- Hover: shows the open note and how many notes you have.
- `/np minimap` hides the button. Type it again to show it.

## Slash commands

Type `/np` or `/notepad`, followed by:

| Command | What it does |
|---|---|
| (nothing) | Opens or closes the window |
| `new` | Opens the window and adds a new note |
| `list` | Opens the window and adds a new checklist |
| a number, e.g. `2` | Opens note 2 (any number works) |
| a name, e.g. `raid` | Opens the note with that name, or else the first whose name starts with it (A-Z not case-sensitive). Command words win, so `/np reset` still resets. |
| `open <name>` | Always opens by name, also for a note named like a command |
| `undo` | Brings back the last deleted note or checklist lines |
| `size [10-18]` | Sets the text size (see [Settings](#settings)) |
| `opacity [30-100]` | Sets the opacity |
| `lock` | Locks or unlocks the window |
| `remember` | Turns "Open after login" on or off |
| `reset` | Moves the window back to the middle, to its normal size, and unfolds it |
| `minimap` | Hides or shows the minimap button |
| `selftest` | Checks the addon (see [Self-test](#self-test)) |
| `help` | Lists the commands |

A word that is not a command and matches no note says "No note starting with ...".

## Self-test

If something looks wrong, type `/np selftest` (or `/np selftest full` for a longer check). It checks the addon in the game and shows one line. Copy that line and send it with your [GitHub issue](https://github.com/gettic/NotePad/issues).

## For developers

The addon lives in `NotePad\`. It uses no libraries and only the game's own pictures. Files load in this order (see `NotePad_Forever.toc`):

| File | Job |
|---|---|
| `Core.lua` | Saved data, undo, start-up, the slash commands and the key binding's names |
| `Window.lua` | The window, the text box, moving, resizing and folding |
| `Tabs.lua` | The tab row: add, switch, rename, move, convert and delete notes |
| `Checklist.lua` | The checklist view: lines, ticks, items, drag and drop |
| `Settings.lua` | Text size and fonts, opacity, lock, open after login, the cog and its menu |
| `Minimap.lua` | The minimap button |
| `SelfTest.lua` | `/np selftest` |

`Bindings.xml` (not in the `.toc`, the game loads it by itself) adds the key binding.

Saved data is in `NotePadDB` (one for the whole account): the notes (title and text each; checklists also keep their lines), which one is open, the last 3 deleted notes, the window's place, size and folded state, the settings (text size, opacity, lock, open after login), and the minimap button's place and whether it is hidden.

## Licence

All rights reserved. See [LICENSE](LICENSE).
