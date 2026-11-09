#!/usr/bin/env bash
set -euo pipefail

LOCK="$XDG_RUNTIME_DIR/lockscreen.lock"

# 子脚本内部独立打开锁文件fd，抢排他非阻塞锁
exec 200>"$LOCK"
if ! flock -n 200; then
    echo "lockscreen.sh: already running, skip" >&2
    exit 0
fi

# 兜底：检查hyprlock进程，防止异常绕过flock
if pidof -x hyprlock >/dev/null; then
    echo "lockscreen.sh: hyprlock already exists, skip" >&2
    exit 0
fi

systemd-run --user --scope hyprlock -q
#hyprlock -q
ret=$?

if [[ $ret -eq 0 ]]; then
    echo "lockscreen.sh: Unlock successful"
    notify-send -a "BreakingBad" -i /home/swq/.config/hypr/images/avatar/heisenberg.png "✅ 登录成功" "You're goddamn right."
fi
