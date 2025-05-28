#!/usr/bin/env bash

# ===============================
# Server 2 Configuration Script (deploy_sv2.sh)
# Installs and configures OwnCloud, MariaDB, Samba, NRPE, and Fail2Ban
# Based on raw_server2.sh commands
# ===============================

# Função para log com timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a output_sv2.txt
}

# Redirecionar toda a saída para output_sv2.txt e também para o terminal
exec > >(tee -a output_sv2.txt)
exec 2>&1

log "=== INICIANDO SCRIPT DEPLOY_SV2.SH ==="

# Determine script and config directories
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONF_DIR="${SCRIPT_DIR}/conf"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Configuration variables
MY_DOMAIN="owncloud.cgs6.local"
DB_NAME="owncloud"
DB_USER="owncloud"
DB_PASS="OwncloudDB#password123"
ADMIN_USER="admin"
ADMIN_PASS="OwnCloud#server2_password123"
SAMBA_USER="grupo6"
SAMBA_PASS="grupo6_samba123!"

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

# 1. Set hostname and update system
log "=== SETTING HOSTNAME AND UPDATING SYSTEM ==="
echo $MY_DOMAIN
hostnamectl set-hostname $MY_DOMAIN
hostname -f
log "Hostname set to: $(hostname -f)"

apt update && apt upgrade -y

# 2. Create OCC Script Helper
log "=== CREATING OCC SCRIPT HELPER ==="
FILE="/usr/local/bin/occ"
cat <<EOM >$FILE
#! /bin/bash
cd /var/www/owncloud
sudo -E -u www-data /usr/bin/php /var/www/owncloud/occ "\$@"
EOM

chmod +x $FILE
log "OCC script helper created"

# 3. Install packages
log "=== INSTALLING PACKAGES ==="
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update && sudo apt upgrade

apt install -y \
  apache2 \
  libapache2-mod-php7.4 \
  mariadb-server openssl redis-server wget \
  php7.4 php7.4-imagick php7.4-common php7.4-curl \
  php7.4-gd php7.4-imap php7.4-intl php7.4-json \
  php7.4-mbstring php7.4-gmp php7.4-bcmath php7.4-mysql \
  php7.4-ssh2 php7.4-xml php7.4-zip php7.4-apcu \
  php7.4-redis php7.4-ldap php-phpseclib

log "Core packages installed successfully"

# 4. Install SMBClient PHP Module
log "=== INSTALLING SMBCLIENT PHP MODULE ==="
apt-get install -y php7.4-smbclient
echo "extension=smbclient.so" > /etc/php/7.4/mods-available/smbclient.ini
phpenmod smbclient
systemctl restart apache2

# Verify SMBClient installation
php -m | grep smbclient
if php -m | grep -q smbclient; then
  log "SMBClient PHP module installed successfully"
else
  log "WARNING: SMBClient PHP module not found"
fi

# 5. Install recommended packages
log "=== INSTALLING RECOMMENDED PACKAGES ==="
apt install -y \
  unzip bzip2 rsync curl jq \
  inetutils-ping ldap-utils \
  smbclient

log "Recommended packages installed successfully"

# 6. Configure Apache2 Virtual Host
log "=== CONFIGURING APACHE2 VIRTUAL HOST ==="
FILE="/etc/apache2/sites-available/owncloud.conf"
cat <<EOM >$FILE
<VirtualHost *:80>
# uncommment the line below if variable was set
#ServerName \$MY_DOMAIN
DirectoryIndex index.php index.html
DocumentRoot /var/www/owncloud
<Directory /var/www/owncloud>
  Options +FollowSymlinks -Indexes
  AllowOverride All
  Require all granted

 <IfModule mod_dav.c>
  Dav off
 </IfModule>

 SetEnv HOME /var/www/owncloud
 SetEnv HTTP_HOME /var/www/owncloud
</Directory>
</VirtualHost>
EOM

# Test Apache configuration
apachectl -t
if [ $? -eq 0 ]; then
  log "Apache configuration test passed"
else
  log "ERROR: Apache configuration test failed"
  exit 1
fi

# Configure Apache
echo "ServerName $MY_DOMAIN" >> /etc/apache2/apache2.conf
a2dissite 000-default
a2ensite owncloud.conf

log "Apache2 virtual host configured successfully"

# 7. Configure MariaDB
log "=== CONFIGURING MARIADB ==="
sed -i "/\[mysqld\]/atransaction-isolation = READ-COMMITTED\nperformance_schema = on" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl start mariadb

mysql -u root -e \
"CREATE DATABASE IF NOT EXISTS owncloud; \
CREATE USER IF NOT EXISTS 'owncloud'@'localhost' IDENTIFIED BY 'OwncloudDB#password123'; \
GRANT ALL PRIVILEGES ON owncloud.* TO 'owncloud'@'localhost' WITH GRANT OPTION; \
FLUSH PRIVILEGES;"

log "MariaDB configured successfully"

# 8. Enable Apache modules and restart
log "=== ENABLING APACHE MODULES ==="
a2enmod dir env headers mime rewrite setenvif
systemctl restart apache2

log "Apache modules enabled and service restarted"

# 9. Download and install OwnCloud
log "=== DOWNLOADING AND INSTALLING OWNCLOUD ==="
cd /var/www/
wget https://download.owncloud.com/server/stable/owncloud-complete-latest.tar.bz2 && \
tar -xjf owncloud-complete-latest.tar.bz2 && \
chown -R www-data. owncloud

if [ $? -eq 0 ]; then
  log "OwnCloud downloaded and extracted successfully"
else
  log "ERROR: Failed to download or extract OwnCloud"
  exit 1
fi

# 10. Install OwnCloud
log "=== INSTALLING OWNCLOUD ==="
occ maintenance:install \
--database "mysql" \
--database-name "owncloud" \
--database-user "owncloud" \
--database-pass "OwncloudDB#password123" \
--data-dir "/var/www/owncloud/data" \
--admin-user "admin" \
--admin-pass "OwnCloud#server2_password123"

if [ $? -eq 0 ]; then
  log "OwnCloud installed successfully"
else
  log "ERROR: OwnCloud installation failed"
  exit 1
fi

# 11. Configure trusted domains
log "=== CONFIGURING TRUSTED DOMAINS ==="
MY_IP=$(hostname -I|cut -f1 -d ' ')
occ config:system:set trusted_domains 1 --value="$MY_IP"
occ config:system:set trusted_domains 2 --value="$MY_DOMAIN"

log "Trusted domains configured: $MY_IP and $MY_DOMAIN"

# 12. Configure background jobs and cron
log "=== CONFIGURING BACKGROUND JOBS ==="
occ background:cron

echo "*/15  *  *  *  * /var/www/owncloud/occ system:cron" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
echo "0  2  *  *  * /var/www/owncloud/occ dav:cleanup-chunks" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data

log "Background jobs and cron configured"

# 13. Configure cache and locks
log "=== CONFIGURING CACHE AND LOCKS ==="
occ config:system:set \
   memcache.local \
   --value '\OC\Memcache\APCu'
occ config:system:set \
   memcache.locking \
   --value '\OC\Memcache\Redis'
occ config:system:set \
   redis \
   --value '{"host": "127.0.0.1", "port": "6379"}' \
   --type json

log "Cache and locks configured"

# 14. Configure log rotation
log "=== CONFIGURING LOG ROTATION ==="
FILE="/etc/logrotate.d/owncloud"
sudo cat <<EOM >$FILE
/var/www/owncloud/data/owncloud.log {
  size 10M
  rotate 12
  copytruncate
  missingok
  compress
  compresscmd /bin/gzip
}
EOM

log "Log rotation configured"

# 15. Finalize OwnCloud setup
log "=== FINALIZING OWNCLOUD SETUP ==="
cd /var/www/
chown -R www-data. owncloud

occ -V
echo "Your ownCloud is accessable under: "$MY_IP
echo "Your ownCloud is accessable under: "$MY_DOMAIN
echo "The Installation is complete."

log "OwnCloud setup completed"
log "Access URL: http://$MY_IP"
log "Access URL: http://$MY_DOMAIN"

# 16. Configure UFW Firewall (Basic)
log "=== CONFIGURING BASIC FIREWALL ==="
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw --force enable

log "Basic firewall configured"

# 17. Configure Samba
log "=== CONFIGURING SAMBA ==="
apt update && sudo apt upgrade -y
apt install samba -y

log "Samba version: $(samba --version)"

# Add Samba configuration
cat >> /etc/samba/smb.conf << EOF

[grupo6]
   comment = Pasta partilhada grupo 6
   path = /home/grupo6/pasta_grupo6
   valid users = grupo6
   browseable = yes
   writable = yes
   guest ok = no
   read only = no
EOF

# Create Samba user and directory
sudo adduser grupo6
sudo smbpasswd -a grupo6
mkdir -p /home/grupo6/pasta_grupo6
sudo chown grupo6:grupo6 /home/grupo6/pasta_grupo6
systemctl restart smbd

# Allow Samba through firewall
ufw allow 445/tcp

log "Samba configured successfully"

# 18. Install and configure NRPE
log "=== INSTALLING NRPE ==="
sudo apt-get update
sudo apt-get install -y gcc make libssl-dev xinetd wget

cd /tmp
wget https://github.com/NagiosEnterprises/nrpe/archive/nrpe-4.1.0.tar.gz
tar xzf nrpe-4.1.0.tar.gz
cd nrpe-nrpe-4.1.0
./configure --enable-command-args
make all

sudo make install-groups-users
sudo make install
sudo make install-config
sudo make install-init
sudo systemctl enable nrpe
sudo systemctl start nrpe

log "NRPE installed successfully"

# 19. Deploy NRPE config
log "=== DEPLOYING NRPE CONFIG ==="
NRPE_SRC="${CONF_DIR}/server02_nrpe.cfg"
NRPE_DEST="/usr/local/nagios/etc/nrpe.cfg"

if [[ -f "$NRPE_SRC" ]]; then
  cp "$NRPE_SRC" "$NRPE_DEST"
  chown nagios:nagios "$NRPE_DEST"
  chmod 640 "$NRPE_DEST"
  log "NRPE configuration deployed from $NRPE_SRC"
else
  log "WARNING: NRPE config file not found: $NRPE_SRC"
fi

# Allow NRPE through firewall
sudo ufw allow 5666/tcp

# Create necessary directories
sudo mkdir -p /usr/local/nagios/var
sudo chown nagios:nagios /usr/local/nagios/var

sudo systemctl restart nrpe
sudo systemctl status nrpe
/usr/local/nagios/libexec/check_nrpe -H localhost

log "NRPE configured and tested"

# 20. Install monitoring dependencies
log "=== INSTALLING MONITORING DEPENDENCIES ==="
sudo apt install nagios-plugins nagios-plugins-contrib

# 21. Deploy custom monitoring scripts
log "=== DEPLOYING CUSTOM MONITORING SCRIPTS ==="

# Deploy check_smb_share
if [[ -f "${SCRIPTS_DIR}/check_smb_share" ]]; then
  cp "${SCRIPTS_DIR}/check_smb_share" "/usr/lib/nagios/plugins/check_smb_share"
  chmod +x "/usr/lib/nagios/plugins/check_smb_share"
  log "check_smb_share deployed"
else
  log "WARNING: check_smb_share not found in scripts directory"
fi

# Deploy other monitoring scripts
for plugin in check_service_cpu.sh check_locks.sh; do
  src="${SCRIPTS_DIR}/$plugin"
  dest="/usr/local/nagios/libexec/$plugin"
  
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
    chmod +x "$dest"
    chown nagios:nagios "$dest"
    log "$plugin deployed"
  else
    log "WARNING: $plugin not found in scripts directory"
  fi
done

sudo systemctl restart nrpe

log "Custom monitoring scripts deployed"

# 22. Configure Fail2Ban
log "=== CONFIGURING FAIL2BAN ==="
apt install fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Deploy custom filters from conf directory
OWNCLOUD_FILTER_SRC="${CONF_DIR}/server02_owncloud-auth.conf"
SAMBA_FILTER_SRC="${CONF_DIR}/server02_samba-auth.conf"

if [[ -f "$OWNCLOUD_FILTER_SRC" ]]; then
  cp "$OWNCLOUD_FILTER_SRC" /etc/fail2ban/filter.d/owncloud-auth.conf
  chmod 644 /etc/fail2ban/filter.d/owncloud-auth.conf
  log "OwnCloud filter deployed"
else
  log "WARNING: OwnCloud filter not found: $OWNCLOUD_FILTER_SRC"
fi

if [[ -f "$SAMBA_FILTER_SRC" ]]; then
  cp "$SAMBA_FILTER_SRC" /etc/fail2ban/filter.d/samba-auth.conf
  chmod 644 /etc/fail2ban/filter.d/samba-auth.conf
  log "Samba filter deployed"
else
  log "WARNING: Samba filter not found: $SAMBA_FILTER_SRC"
fi

# Deploy Fail2Ban jail configuration
FAIL2BAN_SRC="${CONF_DIR}/server02_fail2ban_jail_local.conf"

if [[ -f "$FAIL2BAN_SRC" ]]; then
  cp "$FAIL2BAN_SRC" /etc/fail2ban/jail.local
  chmod 644 /etc/fail2ban/jail.local
  log "Fail2Ban jail configuration deployed"
else
  log "WARNING: Fail2Ban jail config not found: $FAIL2BAN_SRC"
fi

systemctl restart fail2ban

# Check Fail2Ban status
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status owncloud-auth
fail2ban-client status samba-auth

log "Fail2Ban configured successfully"

# 23. Final verification
log "=== FINAL VERIFICATION ==="

services=("apache2" "mariadb" "redis-server" "smbd" "nrpe" "fail2ban")
for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    log "$service is running"
  else
    log "WARNING: $service is not running"
  fi
done

log "=== SERVER 2 CONFIGURATION COMPLETED ==="
log "OwnCloud Admin: $ADMIN_USER / $ADMIN_PASS"
log "Database: $DB_USER / $DB_PASS"
log "Samba User: $SAMBA_USER / $SAMBA_PASS"
log "OwnCloud URL: http://$MY_IP"
log "OwnCloud URL: http://$MY_DOMAIN"
log "Samba Share: \\\\$MY_IP\\grupo6"
log "Check output_sv2.txt for detailed logs"
