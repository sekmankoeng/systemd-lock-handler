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
        lock &
        ;;
    UNLOCK)
        unlock &
        ;;
    SLEEP)
        lock &
        ;;
    RESUME)
        unlock &
        ;;
    *)
        ;;
esac
