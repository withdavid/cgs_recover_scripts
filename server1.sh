#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Server 1 Configuration Script (server1.sh)
# Applies pre-defined configs and installs services
# ===============================

# Determine script and config directories
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONF_DIR="${SCRIPT_DIR}/conf"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Ensure script is run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Check config directories
if [[ ! -d "$CONF_DIR" ]]; then
  echo "Error: Config directory not found: $CONF_DIR" >&2
  exit 1
fi
if [[ ! -d "$SCRIPTS_DIR" ]]; then
  echo "Error: Scripts directory not found: $SCRIPTS_DIR" >&2
  exit 1
fi

# 1. Update & install packages
apt update -y
apt install -y nginx bind9 bind9utils bind9-doc dnsutils \
               ufw gcc make libssl-dev xinetd wget \
               nagios-plugins nagios-plugins-contrib fail2ban

# 2. Configure UFW
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 5666/tcp
ufw --force enable

# 3. Deploy BIND config
BIND_ZONE_SRC="${CONF_DIR}/server01_dns_zone.conf"
BIND_DB_SRC="${CONF_DIR}/server01_dns_db_local.conf"

echo "Deploying BIND config from $CONF_DIR..."
for src in "$BIND_ZONE_SRC" "$BIND_DB_SRC"; do
  if [[ ! -f "$src" ]]; then
    echo "Error: missing BIND config: $src" >&2
    exit 1
  fi
  echo "Copying $src to target..."
done

# Named includes only named.conf.local, so place zone declaration there
cp "$BIND_ZONE_SRC" /etc/bind/named.conf.local
# Copy the zone database file
cp "$BIND_DB_SRC" /etc/bind/db.cgs6.local
chown root:bind /etc/bind/db.cgs6.local
chmod 644 /etc/bind/db.cgs6.local

echo "Reloading BIND..."
systemctl reload bind9 2>/dev/null || systemctl reload named

# 4. Deploy NRPE config
NRPE_SRC="${CONF_DIR}/server01_nrpe.cfg"
NRPE_DEST="/usr/local/nagios/etc/nrpe.cfg"

echo "Deploying NRPE config..."
if [[ ! -f "$NRPE_SRC" ]]; then
  echo "Error: missing NRPE config: $NRPE_SRC" >&2
  exit 1
fi
cp "$NRPE_SRC" "$NRPE_DEST"
chown nagios:nagios "$NRPE_DEST"
chmod 640 "$NRPE_DEST"

# 5. Deploy custom plugins
echo "Deploying custom plugins..."
for plugin in check_service_cpu.sh check_locks.sh; do
  src="${SCRIPTS_DIR}/$plugin"
  dest="/usr/local/nagios/libexec/$plugin"
  if [[ ! -f "$src" ]]; then
    echo "Error: missing plugin: $src" >&2
    exit 1
  fi
  cp "$src" "$dest"
  chmod +x "$dest"
  chown nagios:nagios "$dest"
  echo "  Installed $plugin"
done

# 6. Deploy Fail2Ban config
FAIL2BAN_SRC="${CONF_DIR}/server01_fail2ban_jail_local.conf"
FAIL2BAN_DEST="/etc/fail2ban/jail.local"

echo "Deploying Fail2Ban config..."
if [[ ! -f "$FAIL2BAN_SRC" ]]; then
  echo "Error: missing Fail2Ban config: $FAIL2BAN_SRC" >&2
  exit 1
fi

# Check if source file is empty
if [[ ! -s "$FAIL2BAN_SRC" ]]; then
  echo "Error: Fail2Ban config file is empty: $FAIL2BAN_SRC" >&2
  exit 1
fi

if [[ -f "$FAIL2BAN_DEST" ]]; then
  mv "$FAIL2BAN_DEST" "${FAIL2BAN_DEST}.bak"
  echo "  Backed up existing jail.local"
fi

# Copy file and verify
cp "$FAIL2BAN_SRC" "$FAIL2BAN_DEST"
chmod 644 "$FAIL2BAN_DEST"

# Verify the file was copied correctly
if [[ ! -s "$FAIL2BAN_DEST" ]]; then
  echo "Error: Failed to copy Fail2Ban config or file is empty" >&2
  # Try to restore from backup if available
  if [[ -f "${FAIL2BAN_DEST}.bak" ]]; then
    echo "  Restoring from backup..."
    cp "${FAIL2BAN_DEST}.bak" "$FAIL2BAN_DEST"
  fi
  exit 1
fi

echo "Fail2Ban config file installed successfully."

# 7. Enable & restart core services
echo "Enabling and restarting services..."
systemctl enable nginx bind9 fail2ban
systemctl restart nginx bind9 fail2ban

# 8. Ensure NRPE service
echo "Ensuring NRPE service is running..."
if command -v nrpe &>/dev/null; then
  update-rc.d nrpe defaults || true
  service nrpe restart || service nrpe start
else
  echo "Warning: NRPE not installed." >&2
fi

# Done
echo "Server 1 configuration applied successfully."
