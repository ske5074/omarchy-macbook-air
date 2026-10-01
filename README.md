# Omarchy on a 2018 MacBook Air

My customizations for [Omarchy](https://omarchy.org/) on a 2018 MacBook Air (T2, Intel UHD 617).

```
git clone https://github.com/ske5074/omarchy-macbook-air
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
- **Zen browser hardware video decoding**: the UHD 617 can't decode AV1, so AV1 is disabled and YouTube
  falls back to VP9, which the GPU decodes. Written to the default profile's `user.js`; restart Zen to apply.
- **cliamp visualizer off** (`visualizer = "None"` in `~/.config/cliamp/config.toml`).
- **Balanced power profile**: on the 7W i5-8210Y, `performance` mostly adds heat and throttling.
- **Hibernate hidden from the system menu**: the T2 keyboard/trackpad driver (`t2bce_vhci`) can't resume from
  hibernation, leaving no keyboard or trackpad. Suspend works fine and is what closing the lid does.
- **Idle timeouts by power profile**: a user service watches the power profile and runs the screensaver,
  lock, and idle suspend through `swayidle`, using Omarchy's own screensaver, lock, and wake commands. The
  screen always locks before suspending, including manual suspends. Everything respects the bar's Stay Awake
  toggle.

  | Profile | Screensaver | Lock | Suspend |
  |---|---|---|---|
  | Performance | 30 min | 60 min | never |
  | Balanced | 15 min | 30 min | 10 min |
  | Power-saver | 5 min | 10 min | 5 min |

  These are the defaults. The times live in `~/.config/omarchy/idle-by-powerprofile.json` (created on first
  run, kept on re-runs). Change them in the power panel (below) or with
  `idle-by-powerprofile set <screensaver|lock|suspend> <seconds>`, which edits the active profile.

  Omarchy's own idle timer is set to a week in `shell.json` once, so it never fires first. The times aren't
  kept in `shell.json` because every write to it makes the shell rebuild the bar.
- **Idle controls in the power panel**: the battery panel in the bar gets an Idle section for the active
  profile, with editable screensaver, lock, and suspend times in minutes (suspend 0 = never) and a Stay Awake
  switch. It's a clone of Omarchy's power panel (`~/.config/omarchy/plugins/$USER.power`) with
  `files/power-panel-idle.patch` applied, so it no longer picks up Omarchy's updates to that panel. To refresh
  it, delete the clone and re-run `./install.sh`, which re-clones the current panel and re-applies the patch.

  I've suggested building per-profile idle times, idle suspend, and these panel controls into Omarchy:
  [omacom/omarchy#13960](https://github.com/omacom/omarchy/discussions/13960). If that lands, this step and
  the idle script above can be dropped in favor of the built-in version.

## Files

- `install.sh`: applies everything
- `files/sysstats`: bar widget script, installed to `~/.config/omarchy/bar/scripts/sysstats`
- `files/idle-by-powerprofile`: idle timeout script, installed to `~/.local/bin/idle-by-powerprofile`
- `files/idle-by-powerprofile.service`: systemd user service that runs it, installed to `~/.config/systemd/user/`
- `files/power-panel-idle.patch`: adds the Idle controls to the cloned power panel
