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
  # Already placed; just make sure it refreshes every 10 seconds.
  if jq -e '[.bar.layout[][] | select(.id == "sysstats") | .interval] | all(. == 10)' "$shell_json" >/dev/null; then
    echo "widget already in bar layout"
  else
    cp "$shell_json" "$shell_json.bak.$stamp"
    jq --indent 2 '(.bar.layout[][] | select(.id == "sysstats") | .interval) = 10' "$shell_json.bak.$stamp" > "$shell_json"
    echo "refresh interval set to 10 seconds (backup: $shell_json.bak.$stamp)"
  fi
else
  cp "$shell_json" "$shell_json.bak.$stamp"
  widget='{"id":"sysstats","type":"command","exec":"~/.config/omarchy/bar/scripts/sysstats","interval":10,"onClick":"omarchy-launch-or-focus-tui btop"}'
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

# 8. Hide Hibernate from the system menu: the T2 drivers (t2bce_vhci) can't
# resume from hibernation, so the keyboard and trackpad are dead afterwards.
step "Hiding Hibernate from the system menu"
menu_jsonc="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if grep -qs '"system.hibernate"' "$menu_jsonc"; then
  echo "already hidden"
else
  if [[ -f $menu_jsonc ]]; then
    cp "$menu_jsonc" "$menu_jsonc.bak.$stamp"
  else
    mkdir -p "$(dirname "$menu_jsonc")"
    echo '{' > "$menu_jsonc.bak.$stamp"
    echo '}' >> "$menu_jsonc.bak.$stamp"
  fi
  # Reusing the id overrides the default entry; a false "when" hides it.
  # Insert just before the closing brace.
  awk -v last="$(grep -n '^}' "$menu_jsonc.bak.$stamp" | tail -1 | cut -d: -f1)" '
    NR == last {
      print "  // Hide Hibernate: the T2 drivers lose the keyboard/trackpad on hibernate resume."
      print "  \"system.hibernate\": {\"when\":\"false\"},"
    }
    { print }' "$menu_jsonc.bak.$stamp" > "$menu_jsonc"
  command -v omarchy &>/dev/null && omarchy menu refresh &>/dev/null || true
  echo "hidden (backup: $menu_jsonc.bak.$stamp)"
fi

# 9. Idle timeouts by power profile: swayidle runs the screensaver, lock, and suspend,
# and locks the screen before every sleep.
step "Setting idle timeouts by power profile"
if pacman -Q swayidle &>/dev/null; then
  echo "swayidle already installed"
else
  sudo pacman -S --needed --noconfirm swayidle
fi
if [[ -f $shell_json ]]; then
  cp "$shell_json" "$shell_json.bak.$stamp"
  echo "shell.json backup: $shell_json.bak.$stamp"
fi
install -Dm755 "$here/files/idle-by-powerprofile" "$HOME/.local/bin/idle-by-powerprofile"
install -Dm644 "$here/files/idle-by-powerprofile.service" "$HOME/.config/systemd/user/idle-by-powerprofile.service"
systemctl --user daemon-reload
systemctl --user enable idle-by-powerprofile.service >/dev/null 2>&1
# Restart so a re-run picks up an updated script.
systemctl --user restart idle-by-powerprofile.service
echo "enabled (times are set in files/idle-by-powerprofile)"

# 10. Idle controls in the bar's power panel: clone the built-in panel and patch in
# an Idle section with editable times and a Stay Awake switch (uses step 9's script).
step "Adding idle controls to the power panel"
power_plugin="$HOME/.config/omarchy/plugins/$USER.power"
if [[ -f $power_plugin/Panel.qml ]] && grep -q 'id: idleSetProc' "$power_plugin/Panel.qml"; then
  echo "already added"
elif ! command -v omarchy &>/dev/null; then
  echo "omarchy command not found; skipping"
else
  [[ -f $shell_json ]] && cp "$shell_json" "$shell_json.bak.$stamp"
  # An older read-only Idle section: move that clone aside (outside plugins/, so the
  # shell doesn't load it) and re-clone, so the patch applies to a clean panel.
  if [[ -f $power_plugin/Panel.qml ]] && grep -q 'id: idleProc' "$power_plugin/Panel.qml"; then
    mv "$power_plugin" "$HOME/.config/omarchy/$USER.power.bak.$stamp"
    echo "replacing the older version (backup: ~/.config/omarchy/$USER.power.bak.$stamp)"
  fi
  [[ -d $power_plugin ]] || omarchy plugin clone omarchy.power
  if patch -s -d "$power_plugin" -p1 --dry-run < "$here/files/power-panel-idle.patch" >/dev/null; then
    patch -s -d "$power_plugin" -p1 --no-backup-if-mismatch < "$here/files/power-panel-idle.patch"
    echo "added to $power_plugin"
  else
    echo "patch doesn't apply to this Omarchy's power panel; update files/power-panel-idle.patch"
  fi
fi

# 11. Screenshot on Super+Shift+S: the MacBook keyboard has no Print key.
# Omarchy binds Super+Shift+S to the Google Maps web app, so unbind that first.
step "Binding Super+Shift+S to screenshot"
bindings_lua="$HOME/.config/hypr/bindings.lua"
if [[ ! -f $bindings_lua ]]; then
  echo "no $bindings_lua found; skipping"
elif grep -q '^o.bind("SUPER + SHIFT + S", .*omarchy-capture-screenshot' "$bindings_lua"; then
  echo "already bound"
else
  cp "$bindings_lua" "$bindings_lua.bak.$stamp"
  # Drop Omarchy's commented-out example, then add the real binding.
  grep -v '^-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")' "$bindings_lua.bak.$stamp" > "$bindings_lua"
  cat >> "$bindings_lua" <<'EOF'

-- Screenshot (no Print key on the MacBook). Replaces the Google Maps web app binding.
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")
EOF
  if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null; then
    hyprctl reload >/dev/null
    hyprctl configerrors
  fi
  echo "bound (backup: $bindings_lua.bak.$stamp)"
fi

# 12. Twingate client (AUR). Joining the network is interactive, so it's left to you.
step "Installing Twingate"
if pacman -Q twingate &>/dev/null; then
  echo "already installed"
elif ! command -v yay &>/dev/null; then
  echo "yay not found; skipping"
else
  yay -S --needed --noconfirm twingate
  echo "installed; run 'sudo twingate setup' to join your network"
fi

# 13. Twingate status in the bar's network panel: clone the built-in panel and
# patch in a badge on the Wi-Fi icon and a Twingate row in the popup.
step "Adding Twingate status to the network panel"
network_plugin="$HOME/.config/omarchy/plugins/$USER.network"
if [[ -f $network_plugin/Panel.qml ]] && grep -q 'id: twingateProc' "$network_plugin/Panel.qml"; then
  echo "already added"
elif ! command -v omarchy &>/dev/null; then
  echo "omarchy command not found; skipping"
else
  [[ -f $shell_json ]] && cp "$shell_json" "$shell_json.bak.$stamp"
  [[ -d $network_plugin ]] || omarchy plugin clone omarchy.network
  if patch -s -d "$network_plugin" -p1 --dry-run < "$here/files/network-panel-twingate.patch" >/dev/null; then
    patch -s -d "$network_plugin" -p1 --no-backup-if-mismatch < "$here/files/network-panel-twingate.patch"
    echo "added to $network_plugin"
  else
    echo "patch doesn't apply to this Omarchy's network panel; update files/network-panel-twingate.patch"
  fi
fi

# 14. Drop key chatter: worn butterfly switches register one tap as two presses.
# interception-tools runs the built-in keyboard through files/key-debounce.c.
step "Filtering keyboard chatter"
if pacman -Q interception-tools &>/dev/null; then
  echo "interception-tools already installed"
else
  sudo pacman -S --needed --noconfirm interception-tools
fi
debounce_bin=/usr/local/bin/key-debounce
debounce_yaml=/etc/interception/udevmon.d/key-debounce.yaml
debounce_tmp="$(mktemp)"
gcc -O2 -o "$debounce_tmp" "$here/files/key-debounce.c"
if cmp -s "$debounce_tmp" "$debounce_bin" && cmp -s "$here/files/key-debounce.yaml" "$debounce_yaml" \
  && systemctl is-active --quiet udevmon; then
  echo "already running"
else
  sudo install -Dm755 "$debounce_tmp" "$debounce_bin"
  sudo install -Dm644 "$here/files/key-debounce.yaml" "$debounce_yaml"
  sudo systemctl enable udevmon >/dev/null 2>&1
  sudo systemctl restart udevmon
  echo "running (threshold 30 ms, set in files/key-debounce.yaml)"
fi
rm -f "$debounce_tmp"

# 15. Key repeat waits 400ms (Omarchy's 250ms caught slow-releasing butterfly keys).
step "Setting key repeat delay to 400ms"
if [[ ! -f $input_lua ]]; then
  echo "no $input_lua found; skipping"
elif grep -q '^hl.config({ input = { repeat_delay = 400 } })' "$input_lua"; then
  echo "already set"
else
  cp "$input_lua" "$input_lua.bak.$stamp"
  cat >> "$input_lua" <<'EOF2'

-- Wait longer before key repeat starts: butterfly keys that release slowly were
-- registering a second character at Omarchy's 250ms default.
hl.config({ input = { repeat_delay = 400 } })
EOF2
  if command -v hyprctl &>/dev/null && hyprctl version &>/dev/null; then
    hyprctl reload >/dev/null
    hyprctl configerrors
  fi
  # fcitx5 handles key repeat and only reads the delay when it starts.
  pgrep -x fcitx5 >/dev/null && setsid -f fcitx5 -r -d --disable notificationitem >/dev/null 2>&1
  echo "set (backup: $input_lua.bak.$stamp)"
fi

printf '\nDone.\n'
