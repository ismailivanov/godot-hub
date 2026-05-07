# **Godot Hub**

**Godot Hub** is a desktop app for managing your Godot Engine versions and projects in one place.
It provides a modern, clean interface for downloading editors, organizing projects, and switching between multiple Godot versions quickly.

> **This is a fork** of [MakovWait/godots](https://github.com/MakovWait/godots) by Maxim Kovkel, maintained by [ismailivanov](https://github.com/ismailivanov).

<p align="center">
<img width="1202" height="735" alt="image" src="https://github.com/user-attachments/assets/f0ec144d-3808-485b-b7da-64afe1ff81e0" />
</p>

## **Installation**

### **Windows**
- Download the ZIP, extract it, and run the executable.

### **Linux**
- Unzip and launch the binary directly.

### **macOS**
- Unzip and run **Godot Hub.app**.
- If needed, remove quarantine:
  ```sh
  sudo xattr -r -d com.apple.quarantine /Applications/Godot\ Hub.app
  ```

Download builds from:  
👉 **[Latest Releases](https://github.com/ismailivanov/godot-hub/releases)**

---

## **Features**

### **Editor management**
- Browse and download Godot editor releases.
- Keep multiple Godot versions side-by-side.
- Import custom local editor binaries.
<img width="1202" height="735" alt="image" src="https://github.com/user-attachments/assets/f5979436-6c28-45bd-9030-659c9c7566c9" />


### **Project management**
- Add, import, organize, and launch projects.
- Bind projects to specific editor versions.
- Drag and drop `project.godot` or project folders.

### **News**
- Built-in Godot news feed (RSS) with thumbnail previews.
- Unread indicator — a red dot appears on the News button when new articles are available.
- Search/filter articles by title.
<img width="1202" height="735" alt="image" src="https://github.com/user-attachments/assets/38ee2865-63fa-4676-bd14-cb071d0da845" />


### **Modern UI**
- Redesigned sidebar layout with smoother navigation.
- New app icon and updated theme.
- HiDPI-friendly visuals.

### **Linux .desktop integration**
- Automatically creates a `~/.local/share/applications` entry when an editor is added.
- Removes the entry when the editor is deleted.
- Updates the entry when the editor is renamed.
- Uses a PNG icon from the editor directory when available, falls back to the `godot` theme icon.

### **CLI support**
- Manage projects and versions from terminal workflows.
- See details in **[CLI Features](.github/assets/FEATURES.md#cli)**.

---

## **Changes from upstream**

| Feature | Status |
|---|---|
| Redesigned UI layout and sidebar | Added |
| News tab with RSS feed and thumbnails | Added |
| Unread badge on News button | Added |
| Linux `.desktop` entry management | Added |
| New update/notification button | Improved |
| Editor install UI | Improved |


---

## **License**
MIT License - see `LICENSE`.
