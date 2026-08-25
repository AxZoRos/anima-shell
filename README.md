<h1 align="center">✨ Anima Shell ✨</h1>

<p align="center">
  <b>A fluid, morphing shell for your Linux desktop with native video wallpapers, shape morph transitions, and directory categorization.</b><br>
  <i>A fork of <a href="https://github.com/caelestia-dots/shell">Caelestia Shell</a></i>
</p>

<div align="center">

</div>

---

<!-- DEMO VIDEO / SCREENSHOT PLACEHOLDER -->
<!-- Replace this section with your video or GIF demo -->
<div align="center">
  <!-- <video src="https://github.com/user-attachments/assets/YOUR_VIDEO_ID" controls width="100%"></video> -->
  <p><i>🎬 Demo video coming soon</i></p>
</div>

---

## 📦 Quick Installation

You can install Anima Shell using the built-in interactive deployment script:

```bash
git clone https://github.com/AxZoRos/anima-shell.git
cd anima-shell
./install.sh
```

The installer will guide you through dependency verification, C++ plugin compilation, video decoder selection, and automatic backup creation of your existing configuration.

---

## ⌨️ Launcher Keybindings & Shortcuts

When browsing wallpapers in the launcher, you can use the following shortcuts:

| Shortcut | Action |
| :--- | :--- |
| `Ctrl + B` | Toggle / cycle info badges mode (Format, FPS, Bitrate) |
| `Ctrl + R` | Pick a random wallpaper from the current list |
| `Ctrl + Tab` | Cycle filter mode forward (`All` → `Static` → `Animated`) |
| `Ctrl + Shift + Tab` | Cycle filter mode backward |
| `Alt + Left` / `Alt + H` | Switch to the previous category folder |
| `Alt + Right` / `Alt + L` | Switch to the next category folder |
| `Alt + 1` .. `Alt + 9` | Jump directly to the N-th category folder |
| `Up` / `Down` (or Vim `Ctrl+J` / `Ctrl+K`) | Navigate wallpaper cards |
| `Enter` | Apply selected wallpaper and close launcher |
| `Escape` | Close launcher without changes |

---

## 🎮 Interactive Badges, Hover Capsule & Hidden Controls

We love micro-interactions, so here are a few hidden gems packed into the launcher:

### 🃏 The Expanding "Random" Capsule
> *Don't forget to hover over the "Random" button — it expands to reveal 2 hidden buttons.*

* **Simply hover your mouse** over the `shuffle` (Random) button: the capsule will smoothly slide open to reveal:
  * 👁️ **Badge Toggle Button** (`badge` / `label_off` icon) — Instantly show or hide all info badges across all wallpaper cards in one click.
  * 🔄 **Full Rescan Button** (`refresh` icon) — Forces a complete re-scan of video metadata and regenerates all thumbnails from scratch.

### 🏷️ Interactive Thumbnail Badges
Every wallpaper card displays interactive badges (Format, FPS, Bitrate):
* **Left Click on any badge**: Cycles its position **clockwise** through the four corners of the card.
* **Right Click on any badge**: Hides that specific badge.
* *(Accidentally hid a badge? Just hover over the Random button and click the badge toggle to bring them all back).*

### ⚡ Background Scanning Indicator (`burst_mode`)
> [!NOTE]
> When you add new video wallpapers or hit **Full Rescan**, a status pill with a **`burst_mode`** icon and a countdown number will appear next to the Random capsule.
>
> If you notice a temporary spike in CPU usage during this time, **don't worry**. It's just `ffmpeg` and `ffprobe` extracting crisp video thumbnails and probing stream metadata. We run them with low thread priorities (`nice`/`ionice`) so your desktop stays buttery smooth. Once the countdown hits 0, CPU usage drops right back to idle.

---

## ⚙️ Nexus Settings & Hardware Decoders

Inside the **Nexus → Wallpaper & Style** page, you have full control over the engine:

* **Hardware Video Decoder**:
  * **VA-API** *(Recommended)* — Best choice for 90% of Linux setups (Intel integrated graphics, AMD Radeon, and open-source Mesa drivers). Minimal CPU overhead.
  * **CUDA / NVDEC** — For systems with proprietary NVIDIA drivers.
  * **Software (CPU)** — Safe universal fallback for VMs or systems without hardware video decoding.
* **Auto-Pause Rules**: Configure whether video wallpapers pause when games or fullscreen apps are open.
* **Shape Morph Transitions**: You can switch between Material Shape morphing and classic cross-fade *(...though why would you ever want to disable that awesome morph animation, right?)*.

---

## 📁 Modified & Added Files

Here is the complete list of files touched or created in this shell fork:

| File | Type | Description |
| :--- | :--- | :--- |
| `install.sh` | `NEW` | Interactive multi-distro deployment script and backup manager. |
| `modules/background/VideoWallpaper.qml` | `NEW` | High-performance QtMultimedia video wallpaper component with first-frame freeze. |
| `modules/background/Wallpaper.qml` | `MODIFIED` | Double-buffered layer switching between static images and videos with Material Shape masks. |
| `modules/launcher/Content.qml` | `MODIFIED` | Launcher category bar, expanding action capsule, and custom keybindings. |
| `modules/launcher/WallpaperList.qml` | `MODIFIED` | PathView velocity debounce and smooth scrolling tuning. |
| `modules/launcher/items/WallpaperItem.qml` | `MODIFIED` | Interactive launcher cards with dynamic format, FPS, and bitrate badges. |
| `modules/nexus/common/WallItem.qml` | `MODIFIED` | Grid item component with responsive format badge display. |
| `modules/nexus/pages/WallpaperAndStyle.qml` | `MODIFIED` | Background settings page with pause rules and hardware decoder selection. |
| `modules/nexus/pages/wallandstyle/WallpaperCategory.qml` | `MODIFIED` | Subfolder category browsing view in Nexus. |
| `modules/nexus/pages/wallandstyle/WallpaperSelect.qml` | `MODIFIED` | Responsive grid view with category filters and memory persistence. |
| `plugin/src/Caelestia/Models/filesystemmodel.cpp` | `MODIFIED` | C++ fixes for root recursive directory scanning and async deduplication locks. |
| `services/Colours.qml` | `MODIFIED` | Synchronized Material You palette extraction for video wallpaper frames. |
| `services/WallpaperPauser.qml` | `NEW` | Smart playback manager that pauses video playback on fullscreen apps, lockscreen, or sleep. |
| `services/Wallpapers.qml` | `MODIFIED` | Core wallpaper service with video format detection, directory scanning, and memory. |
| `services/WallpaperThumbQueue.qml` | `NEW` | Multi-threaded asynchronous video thumbnailing and metadata queue with spiral prioritization. |

---

## 🏆 The "Involuntary" Hall of Fame (Credits & Origins)

This project brings together and adapts ideas from several community forks and the upstream project. 

Huge thanks to the creators for their *involuntary* assistance (haha!) — I essentially borrowed the best bits from each, adapted them, rewrote what was broken, and polished it into a unified product:

* **[caelestia-dots/caelestia](https://github.com/caelestia-dots/caelestia)** — The bedrock. The absolute masterpiece of a desktop shell upon which all this is built.
* **[adiambassador/caelestia-aw](https://github.com/adiambassador/caelestia-aw)** — The original spark and genesis of this project. It gifted the initial idea of animated wallpapers in Caelestia and inspired me to take it further.
* **[SunnydeuS/Caelestia-Live-Wallpapers-Integration](https://github.com/SunnydeuS/Caelestia-Live-Wallpapers-Integration)** — The brilliant idea of displaying live badges right on the wallpaper thumbnails. I was breaking my head over how to put FPS, bitrate, and format right under the user's nose, and this was the eureka moment.
* **[dim-ghub/midnight-shell](https://github.com/dim-ghub/midnight-shell)** — The glorious Material Shape morph transitions between wallpapers. It's just too cool not to have.

Without these projects and the people behind them, Anima Shell wouldn't exist.

---

## 🤝 Transparency & AI Collaboration

You might wonder who "we" refers to throughout parts of this project. To be completely transparent: "we" is myself and AI. This fork was created, debugged, and refined with AI pair-programming. I don't intend to hide it, as I believe transparency about AI-assisted development is important.

---

## 🔮 Future Roadmap & Original Docs

Who knows how this will evolve — maybe down the line, this fork will expand into a full standalone ecosystem touching every aspect of the desktop shell. But for now, it's focused on making live wallpapers feel completely native, ultra-responsive, and buttery smooth.

For full documentation on base Caelestia features, keybindings, and widgets, please visit the original repository:
👉 **[caelestia-dots/shell](https://github.com/caelestia-dots/shell)**
