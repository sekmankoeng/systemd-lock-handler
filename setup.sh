#!/usr/bin/env bash
set -euo pipefail

# Configuration
SRC_DIR="./"
USER_UNIT_DIR="${HOME}/.config/systemd/user"
BIN_DIR="/usr/local/bin"

SERVICE_FILE="systemd-lock-handler.service"
SCRIPT_FILE="systemd-lock-handler.sh"
LOCKSCREEN_FILE="lockscreen.sh"
# Check if required source files exist
missing=()
check_file() {
  local f="$1"
  if [[ ! -f "${SRC_DIR}/${f}" ]]; then
    missing+=("${f}")
  fi
}
check_file "${SERVICE_FILE}"
check_file "${SCRIPT_FILE}"

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
cp -vn "${SRC_DIR}${SERVICE_FILE}" "${USER_UNIT_DIR}/"

# Copy executable scripts to /usr/local/bin (requires sudo)
echo "==> Copy scripts to ${BIN_DIR} (requires sudo)"
sudo cp -vn "${SRC_DIR}${SCRIPT_FILE}" "${BIN_DIR}/"
sudo cp -vn "${SRC_DIR}${LOCKSCREEN_FILE}" "${BIN_DIR}/"
# Set executable permissions
echo "==> Set executable permission"
sudo chmod +x "${BIN_DIR}/${SCRIPT_FILE}"
sudo chmod +x "${BIN_DIR}/${LOCKSCREEN_FILE}"
echo
echo "✅ Installation complete!"
echo "Run 'systemctl --user daemon-reload' manually after installation."
echo "Then enable and start service:"
echo "  systemctl --user enable --now systemd-lock-handler.service"
echo "Check status:"
echo "  systemctl --user status systemd-lock-handler.service"
echo "View logs:"
echo "  journalctl --user -u systemd-lock-handler.service -f"

