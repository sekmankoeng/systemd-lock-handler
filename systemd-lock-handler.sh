#!/usr/bin/env bash
set -euo pipefail
# ========== 配置区 ==========
SESSION_ID="${XDG_SESSION_ID:-}"
SERVICE="org.freedesktop.login1"
MANAGER_PATH="/org/freedesktop/login1"
MANAGER_IFACE="org.freedesktop.login1.Manager"
SESSION_IFACE="org.freedesktop.login1.Session"

SIGNAL_LOCK="Lock"
SIGNAL_UNLOCK="Unlock"
SIGNAL_PFS="PrepareForSleep"

DEBOUNCE_MS=500
WAIT_MAX=3000        # 等待锁屏最大毫秒
POLL_INTERVAL=200    # 轮询间隔毫秒

LAST_LOCK_TS=0
LAST_UNLOCK_TS=0
LAST_SLEEP_TS=0
LAST_RESUME_TS=0

FIFO_EVT="${XDG_RUNTIME_DIR}/systemd_evt.fifo"

# ========== 全局变量 ==========
PID_LOCK=""
PID_UNLOCK=""
PID_PFS=""
PID_INHIBIT=""

# ========== 获取session path ==========
if [[ -z "${SESSION_ID}" ]]; then
    echo "ERROR: XDG_SESSION_ID is empty" >&2
    exit 1
fi

SESSION_RAW=$(busctl --system call "${SERVICE}" "${MANAGER_PATH}" "${MANAGER_IFACE}" GetSession s "${SESSION_ID}")
SESSION_PATH=$(echo "${SESSION_RAW}" | awk '{print $NF}' | tr -d '"')
if [[ -z "${SESSION_PATH}" ]]; then
    echo "ERROR: Cannot get session path for ${SESSION_ID}" >&2
    exit 1
fi

# ========== 进程退出钩子 ==========
cleanup() {
    echo "cleanup: stopping listeners and cleaning resources"
    [[ -n "${PID_INHIBIT}" ]] && kill "${PID_INHIBIT}" 2>/dev/null || true
    [[ -n "${PID_LOCK}" ]] && kill "${PID_LOCK}" 2>/dev/null || true
    [[ -n "${PID_UNLOCK}" ]] && kill "${PID_UNLOCK}" 2>/dev/null || true
    [[ -n "${PID_PFS}" ]] && kill "${PID_PFS}" 2>/dev/null || true

    # 等待子进程回收，消除 No such process 报错
    wait "${PID_LOCK}" "${PID_UNLOCK}" "${PID_PFS}" "${PID_INHIBIT}" 2>/dev/null || true
    rm -f "${FIFO_EVT}"
    echo "cleanup done"
    exit 0
}
trap cleanup SIGINT SIGTERM

# ========== 睡眠抑制锁：启动时一次性持有，常驻（本方案核心） ==========
# 说明：采用常驻delay inhibitor，休眠到来时logind一定会等待本锁释放；
# 若D-Bus信号丢失，依赖logind的InhibitDelayMaxSec超时兜底，属于上游异常边界
hold_inhibitor() {
    systemd-inhibit --what=sleep \
        --who="systemd-lock-handler" \
        --why="Complete PrepareForSleep actions before system suspend" \
        --mode=delay \
        sleep infinity &
    PID_INHIBIT=$!
}

# ========== LockedHint确认是否已成功锁屏  ==========
is_locked() {
    [[ $(loginctl show-session "${SESSION_ID}" -p LockedHint --value) == "yes" ]]
}

# ========== 非阻塞写入FIFO，避免listener卡住 ==========
send_event() {
    local evt="$1"
    # timeout 0.1s 写入，写不进去直接丢弃事件，防止阻塞
    timeout 0.1s echo "${evt}" >&9 || true
}

# ========== 信号监听 ==========
listen_lock() {
    while true; do
        if busctl --system wait "${SERVICE}" "${SESSION_PATH}" "${SESSION_IFACE}" "${SIGNAL_LOCK}"; then
            echo "busctl captured D-Bus signal: Lock"
            send_event "LOCK"
        else
            echo "listen_lock: busctl wait failed" >&2
            sleep 1
        fi
    done
}

listen_unlock() {
    while true; do
        if busctl --system wait "${SERVICE}" "${SESSION_PATH}" "${SESSION_IFACE}" "${SIGNAL_UNLOCK}"; then
            echo "busctl captured D-Bus signal: Unlock"
            send_event "UNLOCK"
        else
            echo "listen_unlock: busctl wait failed" >&2
            sleep 1
        fi
    done
}

listen_prepareforsleep() {
    while true; do
        out=$(busctl --system wait "${SERVICE}" "${MANAGER_PATH}" "${MANAGER_IFACE}" "${SIGNAL_PFS}")
        ret=$?
        if [[ ${ret} -ne 0 ]]; then
            echo "listen_prepareforsleep: busctl wait failed" >&2
            sleep 1
            continue
        fi
        state=$(echo "${out}" | awk '{print $NF}')
        echo "busctl captured D-Bus signal: PrepareForSleep(${state})"
        if [[ "${state}" == "true" ]]; then
            send_event "SLEEP"
        else
            send_event "RESUME"
        fi
    done
}

# ========== FIFO初始化 ==========
rm -f "${FIFO_EVT}"
mkfifo "${FIFO_EVT}"
exec 9<> "${FIFO_EVT}"
# ========== 常驻抑制锁：启动就拿，全程持有 ==========
hold_inhibitor
echo "Acquired persistent sleep inhibitor, PID_INHIBIT=${PID_INHIBIT}"

# ========== 启动监听子进程 ==========
listen_lock &
PID_LOCK=$!
listen_unlock &
PID_UNLOCK=$!
listen_prepareforsleep &
PID_PFS=$!

echo "Started listening session ${SESSION_PATH}"
echo "PID lock=${PID_LOCK}"
echo "PID unlock=${PID_UNLOCK}"
echo "PID PFS=${PID_PFS}"

# ========== 主循环 ==========
while true; do
    if read -r -u9 evt; then
        case "${evt}" in
            LOCK)
                echo ">> Session(${SESSION_ID}): Lock signal received"
                if is_locked; then
                    echo "Session(${SESSION_ID}): Skip, already locked (LockedHint=yes)"
                    continue
                fi
                LOCK_NOW=$(date +%s%3N)
                if (( LOCK_NOW - LAST_LOCK_TS < DEBOUNCE_MS )); then
                    echo "Session(${SESSION_ID}): Debounce skip lock event"
                    continue
                fi
                LAST_LOCK_TS=${LOCK_NOW}
                echo ">> Session(${SESSION_ID}): Start pre-lock actions"
                /usr/local/bin/lockscreen.sh &
                echo ">> Session(${SESSION_ID}): Lock signal done"
                ;;
            UNLOCK)
                echo ">> Session(${SESSION_ID}): Unlock signal received"
                if ! is_locked; then
                    echo "Session(${SESSION_ID}): Skip, already unlocked (LockedHint=no)"
                    continue
                fi
                UNLOCK_NOW=$(date +%s%3N)
                if (( UNLOCK_NOW - LAST_UNLOCK_TS < DEBOUNCE_MS )); then
                    echo "Session(${SESSION_ID}): Debounce skip unlock event"
                    continue
                fi
                LAST_UNLOCK_TS=${UNLOCK_NOW}
                echo ">> Session(${SESSION_ID}): Start post-unlock actions"
                echo ">> Session(${SESSION_ID}): Unlock signal done"
                ;;
            SLEEP)
                echo ">> System-global: PrepareForSleep(true) signal received"
                CUR_SLEEP_TS=$(date +%s%3N)
                if (( CUR_SLEEP_TS - LAST_SLEEP_TS < DEBOUNCE_MS )); then
                    echo "Debounce duplicate SLEEP event"
                    continue
                fi
                LAST_SLEEP_TS=${CUR_SLEEP_TS}

                if [[ -z "${PID_INHIBIT}" ]]; then
                    echo "WARNING: Already released inhibitor, skip duplicate SLEEP event" >&2
                    continue
                fi

                echo ">> System-global: Start pre-sleep actions"
                /usr/local/bin/lockscreen.sh &

                # 轮询等待锁屏完成，原生bash整数运算
                ELAPSED=0
                while ! is_locked && [ $ELAPSED -lt $WAIT_MAX ]; do
                    sleep "$(awk -v p="$POLL_INTERVAL" 'BEGIN{print p / 1000}')"
                    ELAPSED=$(( ELAPSED + POLL_INTERVAL ))
                done

                if is_locked; then
                    echo "Lock confirmed, now will releasing inhibitor for suspend"
                else
                    echo "WARNING: Timeout waiting for LockedHint, release inhibitor anyway" >&2
                fi
                # 本次休眠放行：释放抑制锁
                if [[ -n "${PID_INHIBIT}" ]]; then
                    kill "${PID_INHIBIT}" 2>/dev/null || true
                    wait "${PID_INHIBIT}" 2>/dev/null || true
                    PID_INHIBIT=""
                fi
                echo ">> System-global: PrepareForSleep(true) signal done"
                ;;
            RESUME)
                echo ">> System-global: PrepareForSleep(false) signal received"
                CUR_RESUME_TS=$(date +%s%3N)
                if (( CUR_RESUME_TS - LAST_RESUME_TS < DEBOUNCE_MS )); then
                    echo "Debounce duplicate RESUME event"
                    continue
                fi
                LAST_RESUME_TS=${CUR_RESUME_TS}

                echo ">> System-global: Start post-resume actions"
                # 唤醒完成后，重新拉起常驻抑制锁，等待下一次休眠
                hold_inhibitor
                echo "Re-acquired persistent sleep inhibitor after wakeup, PID_INHIBIT=${PID_INHIBIT}"
                echo ">> System-global: PrepareForSleep(false) signal done"
                ;;
            *)
                echo "Unknown event: ${evt}"
                ;;
        esac
    fi
done

