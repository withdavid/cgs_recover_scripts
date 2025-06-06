#!/usr/bin/env bash

# ===============================
# Server 1 Configuration Script (server1.sh)
# Applies pre-defined configs and installs services
# ===============================

# Função para log com timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a output.txt
}

# Redirecionar toda a saída para output.txt e também para o terminal
exec > >(tee -a output.txt)
exec 2>&1

log "=== INICIANDO SCRIPT SERVER1.SH ==="

# Determine script and config directories
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONF_DIR="${SCRIPT_DIR}/conf"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Ensure script is run as root
if [[ $(id -u) -ne 0 ]]; then
  log "ERROR: This script must be run as root."
  exit 1
fi

# Check config directories
if [[ ! -d "$CONF_DIR" ]]; then
  log "ERROR: Config directory not found: $CONF_DIR"
  exit 1
fi
if [[ ! -d "$SCRIPTS_DIR" ]]; then
  log "ERROR: Scripts directory not found: $SCRIPTS_DIR"
  exit 1
fi

# 1. Update & install packages
log "=== UPDATING SYSTEM AND INSTALLING PACKAGES ==="
apt update -y
apt install -y nginx bind9 bind9utils bind9-doc dnsutils \
               ufw gcc make libssl-dev xinetd wget \
               nagios-plugins nagios-plugins-contrib fail2ban bc

# 2. Configure UFW
log "=== CONFIGURING FIREWALL RULES ==="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 5666/tcp
ufw --force enable

# 3. Deploy BIND config
log "=== DEPLOYING BIND CONFIG ==="
BIND_ZONE_SRC="${CONF_DIR}/server01_dns_zone.conf"
BIND_DB_SRC="${CONF_DIR}/server01_dns_db_local.conf"

for src in "$BIND_ZONE_SRC" "$BIND_DB_SRC"; do
  if [[ ! -f "$src" ]]; then
    log "ERROR: missing BIND config: $src"
    exit 1
  fi
done

# Named includes only named.conf.local, so place zone declaration there
cp "$BIND_ZONE_SRC" /etc/bind/named.conf.local
# Copy the zone database file
cp "$BIND_DB_SRC" /etc/bind/db.cgs6.local
chown root:bind /etc/bind/db.cgs6.local
chmod 644 /etc/bind/db.cgs6.local

log "Reloading BIND..."
systemctl reload bind9 2>/dev/null || systemctl reload named

# 4. Install and configure NRPE from source
log "=== INSTALLING NRPE FROM SOURCE ==="
cd /tmp
log "Downloading NRPE source..."
wget -q https://github.com/NagiosEnterprises/nrpe/archive/nrpe-4.1.0.tar.gz
tar xzf nrpe-4.1.0.tar.gz
cd nrpe-nrpe-4.1.0

log "Configuring NRPE..."
./configure --enable-command-args

log "Compiling NRPE..."
make all

log "Installing NRPE..."
make install-groups-users
make install
make install-config
make install-init

log "Enabling NRPE service..."
systemctl enable nrpe

# Create necessary directories
mkdir -p /usr/local/nagios/var
chown nagios:nagios /usr/local/nagios/var

# 5. Deploy NRPE config
log "=== DEPLOYING NRPE CONFIG ==="
NRPE_SRC="${CONF_DIR}/server01_nrpe.cfg"
NRPE_DEST="/usr/local/nagios/etc/nrpe.cfg"

log "Deploying NRPE config..."
if [[ ! -f "$NRPE_SRC" ]]; then
  log "ERROR: missing NRPE config: $NRPE_SRC"
  exit 1
fi

cp "$NRPE_SRC" "$NRPE_DEST"
chown nagios:nagios "$NRPE_DEST"
chmod 640 "$NRPE_DEST"

# 6. Deploy custom monitoring scripts
log "=== DEPLOYING CUSTOM MONITORING SCRIPTS ==="

# Deploy monitoring scripts from scripts directory
for plugin in check_service_cpu.sh check_locks.sh; do
  src="${SCRIPTS_DIR}/$plugin"
  dest="/usr/local/nagios/libexec/$plugin"
  
  if [[ ! -f "$src" ]]; then
    log "ERROR: missing plugin: $src"
    exit 1
  fi
  
  cp "$src" "$dest"
  chmod +x "$dest"
  chown nagios:nagios "$dest"
done

log "Custom monitoring scripts deployed successfully"

# 7. Configure Fail2Ban
log "=== CONFIGURING FAIL2BAN ==="

# Voltar ao diretório do script
cd "$SCRIPT_DIR"

FAIL2BAN_SRC="${CONF_DIR}/server01_fail2ban_jail_local.conf"

if [[ ! -f "$FAIL2BAN_SRC" ]]; then
  log "ERROR: missing Fail2Ban config: $FAIL2BAN_SRC"
  exit 1
fi

# Ensure destination directory exists
mkdir -p /etc/fail2ban

# Remove existing jail.local if present
if [[ -f "/etc/fail2ban/jail.local" ]]; then
  rm -f /etc/fail2ban/jail.local
fi

# Copy Fail2Ban configuration
log "Deploying Fail2Ban configuration..."
if cp "$FAIL2BAN_SRC" /etc/fail2ban/jail.local; then
  chmod 644 /etc/fail2ban/jail.local
  log "Fail2Ban configuration deployed successfully"
else
  log "ERROR: Failed to copy Fail2Ban configuration"
  exit 1
fi

# 8. Enable & restart core services
log "=== ENABLING AND RESTARTING SERVICES ==="
systemctl enable nginx bind9 fail2ban nrpe
systemctl restart nginx bind9 fail2ban nrpe

# 9. Verificar status dos serviços
log "=== CHECKING SERVICES STATUS ==="

# Verificar NGINX
if systemctl is-active --quiet nginx; then
  log "NGINX is running"
else
  log "NGINX is not running"
fi

# Verificar BIND
if systemctl is-active --quiet bind9; then
  log "BIND9 is running"
else
  log "BIND9 is not running"
fi

# Verificar NRPE
if systemctl is-active --quiet nrpe; then
  log "NRPE is running"
else
  log "NRPE is not running"
fi

# Verificar Fail2Ban
if systemctl is-active --quiet fail2ban; then
  log "Fail2Ban is running"
  if command -v fail2ban-client &>/dev/null; then
    log "Active jails:"
    fail2ban-client status
  fi
else
  log "Fail2Ban is not running"
fi

# 10. Test NRPE connection
log "=== TESTING NRPE CONNECTION ==="
if command -v /usr/local/nagios/libexec/check_nrpe &>/dev/null; then
  log "Testing NRPE connection..."
  /usr/local/nagios/libexec/check_nrpe -H localhost
else
  log "NRPE check command not found"
fi

# Done
log "=== SERVER 1 CONFIGURATION COMPLETED SUCCESSFULLY ==="
log "Check output.txt for detailed logs"
