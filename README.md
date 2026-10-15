# snap

A one-screenshot shelf for macOS.

Your latest screenshot sits in a small panel in the bottom-right corner. Drag it into as many apps as you like — it's a copy, so it stays on the shelf. Handy for pasting the same screenshot into two AI chats.

When a new screenshot arrives, the previous one is moved to `~/Screenshots/archive/YYYY-MM/`, so your Desktop stops filling up. Nothing is ever deleted.

- Click **×** (or right-click → Hide) to hide the shelf; it also hides itself after 30 seconds
- Right-click for Copy Image, Show in Finder, Quit
- The next screenshot brings it back

## Setup

Turn off the macOS floating thumbnail so screenshots are saved immediately:

```sh
defaults write com.apple.screencapture show-thumbnail -bool false
```

Build, test and install (starts now and at every login):

```sh
make test
make install
```

macOS will ask once for access to your Desktop folder — allow it.

To try it without installing: `make run` (from a normal Terminal).
To stop it and remove it from login: `make uninstall`.

Logs: `~/Library/Logs/snap.log`

## How it's built

- `src/core/` — C++20: FSEvents folder watcher, screenshot detection, archiving
- `src/app/main.mm` — Objective-C++: the floating shelf window and drag-and-drop
- No dependencies beyond the macOS SDK and Xcode command line tools
