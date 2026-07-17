# Godot Hub

Manage Godot Engine versions and projects from one desktop app. Download editors, organize projects, and switch versions fast.

This fork builds on [MakovWait/godots](https://github.com/MakovWait/godots) by Maxim Kovkel. Maintained by [ismailivanov](https://github.com/ismailivanov).

<p align="center">
<img width="1202" height="735" alt="image" src="https://github.com/user-attachments/assets/4301b177-89d3-45c0-8488-45c1000f46fb" />
</p>

## Installation

Download from [Latest Releases](https://github.com/ismailivanov/godot-hub/releases). Pick your platform:

### Windows
1. Download `GodotHub-Windows.zip`.
2. Extract and run the executable.

### Linux

**AppImage (recommended portable download):**
1. Download `GodotHub-x86_64.AppImage`.
2. Make it executable: `chmod +x GodotHub-x86_64.AppImage`.
3. Run it. Future updates replace and reopen the same AppImage automatically.

**Manual install:**
1. Download `GodotHub-Linux.zip`.
2. Extract and run the binary.

**Arch Linux (AUR):**
```sh
yay -S godot-hub-bin
```

### macOS
1. Download `GodotHub-macOS.zip` and extract.
2. Move **GodotHub.app** to `/Applications`.
3. If macOS blocks the app, run:
   ```sh
   sudo xattr -r -d com.apple.quarantine "/Applications/GodotHub.app"
   ```

---

## Features

### Editor Management
- Browse and download Godot releases
- Run multiple Godot versions side-by-side
- Import custom local editor binaries
<img width="1202" height="735" alt="image" src="https://github.com/user-attachments/assets/f5979436-6c28-45bd-9030-659c9c7566c9" />


### Project Management
- Add, import, organize, and launch projects
- Lock projects to specific Godot versions
- Drag and drop `project.godot` files or folders

### News Feed
- Read Godot news with thumbnail previews
- See unread articles at a glance (red dot indicator)
- Search articles by title
<img width="1202" height="735" alt="image" src="https://github.com/user-attachments/assets/38ee2865-63fa-4676-bd14-cb071d0da845" />


### Modern Interface
- Redesigned sidebar for faster navigation
- Updated theme and app icon
- Sharp visuals on HiDPI screens

### Linux Desktop Integration
- Auto-creates `.desktop` entries in `~/.local/share/applications`
- Cleans up entries when you delete editors
- Updates entries when you rename editors
- Uses custom PNG icons or falls back to system theme

### CLI Support
- Control Godot Hub from your terminal
- See [CLI Features](.github/assets/FEATURES.md#cli) for commands

---

## Changes From Upstream

| Feature | Status |
|---|---|
| New Layout & Visual Identity | Added |
| News tab with RSS and thumbnails | Added |
| Unread badge on News | Added |
| Linux `.desktop` management | Added |
| Update button | Improved |
| Editor install screen | Improved |


---

## License
MIT License. See `LICENSE` file.
