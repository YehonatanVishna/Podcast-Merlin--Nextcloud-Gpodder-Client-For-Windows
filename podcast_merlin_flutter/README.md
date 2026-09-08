# Podcast Merlin 🎙️✨

A modern, cross-platform podcast player with native **Nextcloud Podcast** & **gPodder.net** synchronization, designed for Linux, Windows, macOS, and Android.

---

## Features

- 🔄 **Nextcloud & gPodder Sync**: Bi-directional sync of subscriptions and playback positions with offline queuing and collision resolution.
- 📜 **"Up Next" Queue**: Interactive, persistent playback queue with drag-and-drop reordering, swipe-to-remove, and automatic continuous playback.
- 💤 **Sleep Timer**: Built-in sleep timer with presets (5–60m), real-time countdown badge, audio volume fade-out, and "End of Current Episode" mode.
- ⚡ **Variable Speed & Seek Controls**: Fine-grained playback speed (0.5x to 3.0x in 0.1x steps) and user-configurable rewind and fast-forward intervals.
- 🔍 **Multi-Source Discovery**: Search and discover shows via Apple Podcasts and Podcast Index directories.
- 🖥️ **Desktop Ergonomics**: Adaptive desktop sidebar/rail, hardware mouse back/forward button navigation, Linux MPRIS integration, and Windows MSIX packaging.

---

## System Requirements & Dependencies

Podcast Merlin utilizes native system libraries for audio decoding, hardware media controls, and encrypted credential storage.

### Linux Prerequisites

Before building or running on Linux, ensure the required shared libraries are installed on your distribution:

#### Fedora / RHEL
```bash
# Runtime dependencies (to run app)
sudo dnf install -y mpv-libs libsecret gtk3 sqlite-libs

# Build dependencies (to build from source)
sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel mpv-devel libsecret-devel sqlite-devel xz-devel
```

#### Debian / Ubuntu / Linux Mint / Pop!_OS
```bash
# Runtime dependencies (to run app)
sudo apt update && sudo apt install -y libmpv2 libsecret-1-0 libgtk-3-0 libsqlite3-0

# Build dependencies (to build from source)
sudo apt update && sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev libsqlite3-dev liblzma-dev
```

#### Arch Linux / Manjaro
```bash
sudo pacman -S --needed mpv libsecret gtk3 sqlite
```

#### openSUSE
```bash
sudo zypper install -y libmpv2 libsecret-1-0 libgtk-3-0 libsqlite3-0
```

> 📖 **Full Packaging Guide**: For Flatpak manifests, RPM spec files, Debian control files, Snapcraft configs, and AppImage bundling, see [docs/SYSTEM_DEPENDENCIES.md](docs/SYSTEM_DEPENDENCIES.md).

---

### Windows Prerequisites

- **Microsoft Visual C++ Redistributable 2015–2022** (required for C++ runtime).
- All playback (`libmpv-2.dll`) and database (`sqlite3.dll`) binaries are bundled automatically.

To generate a Windows MSIX installer package:
```powershell
flutter pub run msix:create
```

---

## Development

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run automated test suite
flutter test -j 1

# 3. Analyze code
flutter analyze

# 4. Run application
flutter run -d linux      # Linux desktop
flutter run -d windows    # Windows desktop
```
