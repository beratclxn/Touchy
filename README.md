# Touchy

A universal macOS menu bar & Liquid Glass driver that brings full multi-touch, gesture recognition, 4-point calibration, adaptive on-screen touch keyboard, and DDC/CI hardware auto-rotation to external USB-C/HDMI touch displays on macOS.

## Quick Install (One Command)

Paste this into **Terminal** to automatically download, build, and install **Touchy** to `/Applications`:

```sh
curl -fsSL https://raw.githubusercontent.com/beratclxn/Touchy/main/install.sh | zsh
```

### Build from Source Manually

```sh
git clone https://github.com/beratclxn/Touchy.git && cd Touchy && ./build.sh install
```

On first launch macOS will ask for two permissions in **System Settings → Privacy & Security**:
1. **Accessibility** → Touchy (needed to synthesize clicks, drags, scrolling, and zoom)
2. **Input Monitoring** → Touchy (if requested by macOS to read USB HID touch reports)

## Features & Supported Gestures

| Touch / Feature | Action |
|---|---|
| 1-finger tap | Left click (double-tap → double-click) |
| 1-finger drag | Click & drag / text selection / drawing / window snapping |
| 1-finger long-press (0.85 s) | Right click |
| 2-finger tap | Right click |
| 2-finger drag | Smooth pixel scroll + momentum (inertia) |
| 2-finger pinch / spread | Pinch-to-zoom (Safari, Preview, Maps, Figma, etc.) |
| 3-finger swipe left / right | Switch macOS Spaces |
| 3-finger swipe up / down | Mission Control / App Exposé |
| On-Screen Touch Keyboard | Auto-adapts to active macOS keyboard layout (TR-Q, TR-F, EN, DE, FR, ES, etc.) & draggable |
| Traffic Light Expansion | Enlarges window close/minimize/fullscreen buttons on touch for easy tapping |
