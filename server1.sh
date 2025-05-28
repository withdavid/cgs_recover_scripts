#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Server 1 Configuration Script (server1.sh)
# Copies pre-defined configs and installs services
# ===============================

# Variables
DNS_CONF_DIR="./conf"
SCRIPTS_DIR="./scripts"

# Ensure script is run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root."
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
cp "${DNS_CONF_DIR}/server01_dns_zone.conf" /etc/bind/named.conf.local
cp "${DNS_CONF_DIR}/server01_dns_db_local.conf" /etc/bind/db.cgs6.local
chown root:bind /etc/bind/db.cgs6.local
chmod 644 /etc/bind/db.cgs6.local
systemctl reload bind9 || systemctl reload named

# 4. Deploy NRPE config
NRPE_CFG_DEST="/usr/local/nagios/etc/nrpe.cfg"
cp "${DNS_CONF_DIR}/server01_nrpe.cfg" "${NRPE_CFG_DEST}"
chown nagios:nagios "${NRPE_CFG_DEST}"
chmod 640 "${NRPE_CFG_DEST}"

# 5. Deploy custom plugins
cp "${SCRIPTS_DIR}/check_service_cpu.sh" /usr/local/nagios/libexec/
cp "${SCRIPTS_DIR}/check_locks.sh" /usr/local/nagios/libexec/
chmod +x /usr/local/nagios/libexec/check_service_cpu.sh
chmod +x /usr/local/nagios/libexec/check_locks.sh
chown nagios:nagios /usr/local/nagios/libexec/check_*.sh

# 6. Deploy Fail2Ban config
if [[ -f /etc/fail2ban/jail.local ]]; then
  mv /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak
fi
cp "${DNS_CONF_DIR}/server01_fail2ban_jail_local.conf" /etc/fail2ban/jail.local
chmod 644 /etc/fail2ban/jail.local
systemctl reload fail2ban

# 7. Enable & start services
systemctl enable nginx bind9 fail2ban
systemctl restart nginx bind9 fail2ban

# 8. Install & start NRPE
# assume NRPE already built; just ensure service is running
if ! command -v nrpe &>/dev/null; then
  echo "NRPE not found: please install NRPE agent separately."
else
  update-rc.d nrpe defaults || true
  service nrpe restart || service nrpe start
fi

echo "Server 1 configuration applied successfully."
