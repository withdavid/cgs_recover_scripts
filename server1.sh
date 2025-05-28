#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Server 1 Configuration Script (server1.sh)
# Applies pre-defined configs and installs services
# ===============================

# Determine script and config directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${SCRIPT_DIR}/conf"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Ensure script is run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root." >&2
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

echo "Deploying BIND configuration from ${CONF_DIR}..."
for src in "$BIND_ZONE_SRC" "$BIND_DB_SRC"; do
  if [[ ! -s "$src" ]]; then
    echo "Error: Source BIND file missing or empty: $src" >&2
    exit 1
  fi
done

cp "$BIND_ZONE_SRC" /etc/bind/named.conf.local
cp "$BIND_DB_SRC" /etc/bind/db.cgs6.local
chown root:bind /etc/bind/db.cgs6.local
chmod 644 /etc/bind/db.cgs6.local

echo "Reloading BIND..."
systemctl reload bind9 2>/dev/null || systemctl reload named

# 4. Deploy NRPE config
NRPE_SRC="${CONF_DIR}/server01_nrpe.cfg"
NRPE_DEST="/usr/local/nagios/etc/nrpe.cfg"

if [[ ! -s "$NRPE_SRC" ]]; then
  echo "Error: NRPE config file missing or empty: $NRPE_SRC" >&2
  exit 1
fi

cp "$NRPE_SRC" "$NRPE_DEST"
chown nagios:nagios "$NRPE_DEST"
chmod 640 "$NRPE_DEST"

echo "NRPE configuration deployed."

# 5. Deploy custom plugins
for plugin in check_service_cpu.sh check_locks.sh; do
  src="${SCRIPTS_DIR}/$plugin"
  dest="/usr/local/nagios/libexec/$plugin"
  if [[ ! -s "$src" ]]; then
    echo "Error: Plugin missing or empty: $src" >&2
    exit 1
  fi
  cp "$src" "$dest"
  chmod +x "$dest"
  chown nagios:nagios "$dest"
done

echo "Custom NRPE plugins deployed."

# 6. Deploy Fail2Ban config
FAIL2BAN_SRC="${CONF_DIR}/server01_fail2ban_jail_local.conf"
FAIL2BAN_DEST="/etc/fail2ban/jail.local"

if [[ ! -s "$FAIL2BAN_SRC" ]]; then
  echo "Error: Fail2Ban source missing or empty: $FAIL2BAN_SRC" >&2
  exit 1
fi
if [[ -f "$FAIL2BAN_DEST" ]]; then
  mv "$FAIL2BAN_DEST" "${FAIL2BAN_DEST}.bak"
fi
cp "$FAIL2BAN_SRC" "$FAIL2BAN_DEST"
chmod 644 "$FAIL2BAN_DEST"

echo "Reloading Fail2Ban..."
systemctl reload fail2ban

# 7. Enable & restart core services
systemctl enable nginx bind9 fail2ban
systemctl restart nginx bind9 fail2ban

echo "Core services enabled and restarted."

# 8. Ensure NRPE service
if command -v nrpe &>/dev/null; then
  echo "Configuring NRPE service..."
  update-rc.d nrpe defaults || true
  service nrpe restart || service nrpe start
else
  echo "Warning: NRPE not installed; please install agent separately." >&2
fi

echo "Server 1 configuration applied successfully."
