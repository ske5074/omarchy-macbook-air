#!/bin/bash
# Omarchy customizations for a 2018 MacBook Air (T2).
# Safe to re-run: each step checks whether it has already been applied.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shell_json="$HOME/.config/omarchy/shell.json"
input_lua="$HOME/.config/hypr/input.lua"
stamp="$(date +%s)"

step() { printf '\n==> %s\n' "$1"; }

# 1. Kate text editor
step "Installing Kate"
if pacman -Q kate &>/dev/null; then
  echo "already installed"
else
  sudo pacman -S --needed --noconfirm kate
fi

# 2. CPU / GPU / memory bar widget
step "Installing CPU/GPU/memory bar widget"
install -Dm755 "$here/files/sysstats" "$HOME/.config/omarchy/bar/scripts/sysstats"

if [[ ! -f $shell_json ]]; then
  echo "no $shell_json found; skipping bar layout (run 'omarchy refresh shell' first)"
elif jq -e '[.bar.layout[][] | select(.id == "sysstats")] | length > 0' "$shell_json" >/dev/null; then
  echo "widget already in bar layout"
else
  cp "$shell_json" "$shell_json.bak.$stamp"
  widget='{"id":"sysstats","type":"command","exec":"~/.config/omarchy/bar/scripts/sysstats","interval":2,"onClick":"omarchy-launch-or-focus-tui btop"}'
  # Place it right after the tray, or at the start of the right section.
  jq --argjson w "$widget" '
    .bar.layout.right |= (
      (map(.id) | index("omarchy.tray")) as $i
      | if $i == null then [$w] + . else .[:$i+1] + [$w] + .[$i+1:] end
    )' "$shell_json.bak.$stamp" > "$shell_json"
  echo "added to bar (backup: $shell_json.bak.$stamp)"
fi

# 3. Three-finger trackpad gestures
step "Enabling trackpad gestures"
if [[ ! -f $input_lua ]]; then
  echo "no $input_lua found; skipping"
else
  cp "$input_lua" "$input_lua.bak.$stamp"
  changed=0

  # Left/right: switch workspaces (Omarchy ships this line commented out).
  if ! grep -q '^hl.gesture({ fingers = 3, direction = "horizontal"' "$input_lua"; then
    if grep -q '^-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })' "$input_lua"; then
      sed -i 's|^-- \(hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })\)|\1|' "$input_lua"
    else
      printf '\n-- Swipe left/right to switch workspaces.\nhl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })\n' >> "$input_lua"
    fi
    changed=1
  fi

  # Up: toggle scratchpad (like SUPER + S). Down: toggle fullscreen.
  if ! grep -q '^hl.gesture({ fingers = 3, direction = "up"' "$input_lua"; then
    cat >> "$input_lua" <<'EOF'

-- Swipe up to toggle the scratchpad (like SUPER + S), down to toggle fullscreen.
hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "scratchpad" })
hl.gesture({ fingers = 3, direction = "down", action = "fullscreen", mode = "fullscreen" })
EOF
    changed=1
  fi

  if (( changed )); then
    echo "gestures enabled (backup: $input_lua.bak.$stamp)"
    if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null; then
      hyprctl reload >/dev/null
      hyprctl configerrors
    fi
  else
    rm "$input_lua.bak.$stamp"
    echo "gestures already enabled"
  fi
fi

# 4. Function keys: media keys by default, F1-F12 with Fn
step "Setting function keys to media keys by default"
if grep -qs 'fnmode=1' /etc/modprobe.d/hid_apple.conf; then
  echo "already set"
else
  echo 'options hid_apple fnmode=1' | sudo tee /etc/modprobe.d/hid_apple.conf >/dev/null
  echo 1 | sudo tee /sys/module/hid_apple/parameters/fnmode >/dev/null || true
  echo "set (persists across reboots)"
fi

# 5. Zen browser: hardware video decoding
# The UHD 617 decodes H.264/HEVC/VP9 but not AV1, so disable AV1 and YouTube
# falls back to VP9 on the GPU instead of decoding on the CPU.
step "Configuring Zen for hardware video decoding"
zen_dir="$HOME/.config/zen"
zen_profile=""
if [[ -f $zen_dir/installs.ini ]]; then
  zen_profile="$(sed -n 's/^Default=//p' "$zen_dir/installs.ini" | head -1)"
fi
if [[ -z $zen_profile && -f $zen_dir/profiles.ini ]]; then
  zen_profile="$(sed -n 's/^Path=//p' "$zen_dir/profiles.ini" | head -1)"
fi
if [[ -z $zen_profile || ! -d $zen_dir/$zen_profile ]]; then
  echo "no Zen profile found; skipping (open Zen once, then re-run)"
else
  user_js="$zen_dir/$zen_profile/user.js"
  touch "$user_js"
  added=0
  for pref in \
    'user_pref("media.av1.enabled", false);' \
    'user_pref("media.hardware-video-decoding.force-enabled", true);' \
    'user_pref("media.ffmpeg.vaapi.enabled", true);'; do
    if ! grep -qF "$pref" "$user_js"; then
      echo "$pref" >> "$user_js"
      added=1
    fi
  done
  if (( added )); then
    echo "prefs written to $user_js (restart Zen to apply)"
  else
    echo "already set"
  fi
fi

# 6. Balanced power profile: the 7W i5-8210Y mostly turns 'performance' into heat
step "Setting power profile to balanced"
if ! command -v powerprofilesctl &>/dev/null; then
  echo "power-profiles-daemon not installed; skipping"
elif [[ $(powerprofilesctl get) == balanced ]]; then
  echo "already set"
else
  powerprofilesctl set balanced
  echo "set (power-profiles-daemon remembers it across reboots)"
fi

# 7. cliamp: no visualizer (it was the top CPU user on this 2-core chip)
step "Turning off the cliamp visualizer"
cliamp_conf="$HOME/.config/cliamp/config.toml"
if [[ -f $cliamp_conf ]] && grep -q '^visualizer = "None"' "$cliamp_conf"; then
  echo "already set"
else
  mkdir -p "$(dirname "$cliamp_conf")"
  touch "$cliamp_conf"
  cp "$cliamp_conf" "$cliamp_conf.bak.$stamp"
  # Top-level key, so it must come before any [section]; drop an old value first.
  { echo 'visualizer = "None"'; grep -v '^visualizer *=' "$cliamp_conf.bak.$stamp"; } > "$cliamp_conf"
  if command -v cliamp &>/dev/null && [[ -S $HOME/.config/cliamp/cliamp.sock ]]; then
    cliamp vis None &>/dev/null || true
  fi
  echo "set (backup: $cliamp_conf.bak.$stamp)"
fi

printf '\nDone.\n'
