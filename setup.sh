#!/usr/bin/env bash
set -euo pipefail
# Configuration
SRC_DIR="."
USER_UNIT_DIR="${HOME}/.config/systemd/user"
BIN_DIR="/usr/local/bin"

SLH_SERVICE_FILE="systemd-lock-handler.service"
SLH_SCRIPT_FILE="systemd-lock-handler.sh"
LOCKSCREEN_FILE="L99-lockscreen"
# Check if required source files exist
missing=()
check_file() {
  local f="$1"
  if [[ ! -f "${SRC_DIR}/${f}" ]]; then
    missing+=("${f}")
  fi
}
check_file "${SLH_SERVICE_FILE}"
check_file "${SLH_SCRIPT_FILE}"

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing source files in current directory:"
  printf "  - %s\n" "${missing[@]}"
  exit 1
fi

# Create systemd user unit directory if not exists
echo "==> Prepare user unit directory: ${USER_UNIT_DIR}"
mkdir -p "${USER_UNIT_DIR}"

# Copy user systemd units (no root required)
echo "==> Copy user systemd units"
cp -vn "${SRC_DIR}/${SLH_SERVICE_FILE}" "${USER_UNIT_DIR}/"

# Copy executable scripts to /usr/local/bin (requires sudo)
echo "==> Copy scripts to ${BIN_DIR} (requires sudo)"
sudo cp -vn "${SRC_DIR}/${SLH_SCRIPT_FILE}" "${BIN_DIR}/"
sudo chmod +x "${BIN_DIR}/${SLH_SCRIPT_FILE}"

sudo mkdir -p "${BIN_DIR}/slh.d/"
sudo cp -vn "${SRC_DIR}/slh.d/${LOCKSCREEN_FILE}" "${BIN_DIR}/slh.d/"
sudo chmod -R +x "${BIN_DIR}/slh.d/"
cd "${BIN_DIR}/slh.d/"
sudo ln -s "${LOCKSCREEN_FILE}" "U01-lockscreen"
sudo ln -s "${LOCKSCREEN_FILE}" "S99-lockscreen"

echo
echo "✅ Installation complete!"
echo "Run 'systemctl --user daemon-reload' manually after installation."
echo "Then enable and start service:"
echo "  systemctl --user enable --now systemd-lock-handler.service"
echo "Check status:"
echo "  systemctl --user status systemd-lock-handler.service"
echo "View logs:"
echo "  journalctl --user -u systemd-lock-handler.service -f"

