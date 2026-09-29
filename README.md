# Omarchy on a 2018 MacBook Air

My customizations for [Omarchy](https://omarchy.org/) on a 2018 MacBook Air (T2, Intel UHD 617).

```
git clone https://github.com/<you>/omarchy-macbook-air
cd omarchy-macbook-air
./install.sh
```

The script is safe to re-run. It backs up any config file before changing it (`*.bak.<timestamp>`).

## What it does

- **Kate** text editor
- **CPU / GPU / memory widget** in the bar, refreshed every 2 seconds. Hover for details, click to open btop.
  GPU usage is read from DRM fdinfo, so it needs no root, but only counts your own processes.
- **Three-finger trackpad gestures**
  - left / right: switch workspace
  - up: toggle the scratchpad (same as Super+S)
  - down: toggle fullscreen
- **Function keys**: top row acts as brightness/volume/media keys by default, F1–F12 with Fn (`hid_apple fnmode=1`).

## Files

- `install.sh`: applies everything
- `files/sysstats`: bar widget script, installed to `~/.config/omarchy/bar/scripts/sysstats`
