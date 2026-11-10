# systemd-lock-handler
> A D-Bus event router for lock and suspend signals. It follows SysVinit-style conventions, allowing users to define custom hooks to process these signal events.

`systemd-lock-handler` listens to logind D-Bus signals, including Lock, Unlock, PrepareForSleep(true), and PrepareForSleep(false). It implements signal event handling powered by two core mechanisms:

1. Polling with timeout checks on the session `LockedHint` to implement a synchronous mechanism for lock hooks;
2. Holding a persistent sleep inhibitor lock to achieve synchronous execution of hooks before system sleep/suspend.

It works with an idle management daemon (e.g., swayidle) as the frontend to implement system idle timeout lock and suspend functions.

## ✨ Features
- Listen to logind D-Bus signals: `Lock`, `Unlock`, `PrepareForSleep(true): Sleep`, `PrepareForSleep(false): Resume`
- Long-held sleep inhibitor (`delay` mode) to guarantee pre-suspend workflows finish before suspend
- SysVinit-like style for easy custom signal event hooks, simple implementation.
- Pure bash, no extra dependencies required (only awk, systemd, dbus)
- Designed for Wayland compositors (Sway, Hyprland, Niri, etc.)

## 📦 Architecture
```
┌────────────────────────────────┐
│ logind (logind D-Bus signals)  │
└───────────────┬────────────────┘
                ↓
┌─────────────────────────────────────────────────────┐
│ systemd-lock-handler.service                        │
│ -> systemd-lock-handler.sh                          │
│ (signal listener + inhibitor manager + event router)│
└────────────────┬────────────────────────────────────┘
                 ↓
┌────────────────────────────────────────────────────────────┐
│ SysVinit-like signal-event hooks                           │
│ L:Lock / U:Unlock / S:Sleep / R:Resume                     │
└────────────────┬───────────────────────────────────────────┘
                 ↓
┌────────────────────────────────────────────────────┐
│ Your custom scripts                                │
│ L99-action / U01-action / S99-action / R01-action  │
└────────────────────────────────────────────────────┘
```
You do **not** need to handle D-Bus or inhibitor logic in your own scripts. Just define the hook actions in your SysVinit-like scripts.

## 📋 Requirements
- systemd: loginctl/busctl/systemctl

## 🔨 Installation
```bash
cd systemd-lock-handler/
chmod +x setup.sh
./setup.sh
```

## 🚀 Usage
```bash
# 1. Reload systemd user manager:
systemctl --user daemon-reload

# 2. Enable and start the bridge service:
systemctl --user enable --now systemd-lock-handler.serice

# 3. Check service status:
systemctl --user status systemd-lock-handler.service

# 4. View real-time logs:
journalctl --user -fu systemd-lock-handler.service

# 5. Check system sleep inhibitor
systemd-inhibit

```
## 🧩 Write your custom hook
1. Script naming rule: `[prefix]+[two-digit number]-scriptname`
2. Prefix indicates execution scenario: L: Lock, U: Unlock, S: Sleep, R: Resume
3. Two-digit number defines execution order within the scenario, range `01–99`, executed in ascending order
4. Symbolic links can be created under the `slh.d/` directory to customize script execution order

### Example:
1.`vim slh.d/L99-lockscreen`
```sh
#!/usr/bin/env bash
set -euo pipefail

SESSION_ID="${XDG_SESSION_ID:?}"

# Check LockedHint
is_locked() {
    [[ $(loginctl show-session "$SESSION_ID" -p LockedHint --value) == "yes" ]]
}

lock() {
    if is_locked; then
        echo "$0(${SESSION_ID}): Skip, already locked (LockedHint=yes)"
        return 0
    fi
    # `hyprlock -q` could be replace to your lockscreen tool
    systemd-run --user --scope hyprlock -q
    ret=$?

    if [[ $ret -eq 0 ]]; then
        echo "$0(${SESSION_ID}): Unlock successful"
    fi
}

unlock() {
    if ! is_locked; then
        echo "$0(${SESSION_ID}): Skip, already unlocked (LockedHint=no)"
        return 0
    fi
    # There is NOTHING left to do
}

case "$1" in
    LOCK)
        # Some actions
        lock &
        # Another actions
        ;;
    UNLOCK)
        unlock &
        ;;
    SLEEP)
        lock &
        ;;
    RESUME)
        ;;
    *)
        ;;
esac
```
2.Define execution order for other signal events
```
cd slh.d/

# Set lockscreen hook order for SLEEP signal events.
ln -s L99-lockscreen S99-lockscreen

# Set lockscreen hook order for UNLOCK signal events.
ln -s L99-lockscreen U01-lockscreen
```
> [!NOTE]
> `L99-lockscreen` has defined the handling actions for SLEEP and UNLOCK signal events respectively.
