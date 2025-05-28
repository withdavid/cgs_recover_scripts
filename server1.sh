#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Server 1 Configuration Script (server1.sh)
# Applies pre-defined configs and installs services
# ===============================

# Variables
defaults_user_conf_dir="./conf"
defaults_user_scripts_dir="./scripts"
CONF_DIR="${defaults_user_conf_dir}"
SCRIPTS_DIR="${defaults_user_scripts_dir}"

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
BIND_ZONE_CONF="${CONF_DIR}/server01_dns_zone.conf"
BIND_DB_CONF="${CONF_DIR}/server01_dns_db_local.conf"
if [[ ! -f "$BIND_ZONE_CONF" || ! -f "$BIND_DB_CONF" ]]; then
  echo "Error: BIND config files not found in ${CONF_DIR}" >&2
  exit 1
fi
cp "$BIND_ZONE_CONF" /etc/bind/named.conf.local
cp "$BIND_DB_CONF" /etc/bind/db.cgs6.local
chown root:bind /etc/bind/db.cgs6.local
chmod 644 /etc/bind/db.cgs6.local
systemctl reload bind9 2>/dev/null || systemctl reload named

# 4. Deploy NRPE config
NRPE_SRC="${CONF_DIR}/server01_nrpe.cfg"
NRPE_DEST="/usr/local/nagios/etc/nrpe.cfg"
if [[ ! -f "$NRPE_SRC" ]]; then
  echo "Error: NRPE config file not found: $NRPE_SRC" >&2
  exit 1
fi
cp "$NRPE_SRC" "$NRPE_DEST"
chown nagios:nagios "$NRPE_DEST"
chmod 640 "$NRPE_DEST"

# 5. Deploy custom plugins
for plugin in check_service_cpu.sh check_locks.sh; do
  src="${SCRIPTS_DIR}/$plugin"
  dest="/usr/local/nagios/libexec/$plugin"
  if [[ ! -f "$src" ]]; then
    echo "Error: Plugin not found: $src" >&2
    exit 1
  fi
  cp "$src" "$dest"
  chmod +x "$dest"
  chown nagios:nagios "$dest"
done

# 6. Deploy Fail2Ban config
FAIL2BAN_SRC="${CONF_DIR}/server01_fail2ban_jail_local.conf"
FAIL2BAN_DEST="/etc/fail2ban/jail.local"
if [[ ! -f "$FAIL2BAN_SRC" ]]; then
  echo "Error: Fail2Ban config not found: $FAIL2BAN_SRC" >&2
  exit 1
fi
if [[ -f "$FAIL2BAN_DEST" ]]; then
  mv "$FAIL2BAN_DEST" "${FAIL2BAN_DEST}.bak"
fi
cp "$FAIL2BAN_SRC" "$FAIL2BAN_DEST"
chmod 644 "$FAIL2BAN_DEST"
systemctl reload fail2ban

# 7. Enable & restart core services
systemctl enable nginx bind9 fail2ban
systemctl restart nginx bind9 fail2ban

# 8. Ensure NRPE service
if command -v nrpe &>/dev/null; then
  update-rc.d nrpe defaults || true
  service nrpe restart || service nrpe start
else
  echo "Warning: NRPE not installed; please install agent separately." >&2
fi

echo "Server 1 configuration applied successfully."
