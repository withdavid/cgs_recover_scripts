#!/usr/bin/env bash

# ===============================
# Server 2 Configuration Script (deploy_sv2.sh)
# Installs and configures OwnCloud, MariaDB, Samba, NRPE, and Fail2Ban
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
hostnamectl set-hostname "$MY_DOMAIN"
log "Hostname set to: $(hostname -f)"

apt update && apt upgrade -y

# 2. Create OCC Script Helper
log "=== CREATING OCC SCRIPT HELPER ==="
cat > /usr/local/bin/occ << 'EOF'
#!/bin/bash
cd /var/www/owncloud
sudo -E -u www-data /usr/bin/php /var/www/owncloud/occ "$@"
EOF
chmod +x /usr/local/bin/occ
log "OCC script helper created"

# 3. Install packages
log "=== INSTALLING PACKAGES ==="

# Install software-properties-common first to get add-apt-repository
apt install -y software-properties-common

# Add PHP repository for PHP 8.1
add-apt-repository ppa:ondrej/php -y
apt update && apt upgrade -y

# Install all required packages
apt install -y \
  apache2 \
  libapache2-mod-php8.1 \
  mariadb-server openssl redis-server wget \
  php8.1 php8.1-imagick php8.1-common php8.1-curl \
  php8.1-gd php8.1-imap php8.1-intl \
  php8.1-mbstring php8.1-gmp php8.1-bcmath php8.1-mysql \
  php8.1-ssh2 php8.1-xml php8.1-zip php8.1-apcu \
  php8.1-redis php8.1-ldap php-phpseclib \
  unzip bzip2 rsync curl jq \
  inetutils-ping ldap-utils smbclient \
  samba \
  gcc make libssl-dev xinetd \
  nagios-plugins nagios-plugins-contrib \
  fail2ban bc

# Verify critical packages are installed
if ! command -v apache2 &>/dev/null; then
  log "ERROR: Apache2 installation failed"
  exit 1
fi

if ! command -v php &>/dev/null; then
  log "ERROR: PHP installation failed"
  exit 1
fi

log "All packages installed successfully"

# 4. Install SMBClient PHP Module
log "=== INSTALLING SMBCLIENT PHP MODULE ==="
apt-get install -y php8.1-smbclient
echo "extension=smbclient.so" > /etc/php/8.1/mods-available/smbclient.ini
phpenmod smbclient
systemctl restart apache2

# Verify SMBClient installation
if php -m | grep -q smbclient; then
  log "SMBClient PHP module installed successfully"
else
  log "WARNING: SMBClient PHP module not found"
fi

# 5. Configure Apache2 Virtual Host
log "=== CONFIGURING APACHE2 VIRTUAL HOST ==="
cat > /etc/apache2/sites-available/owncloud.conf << EOF
<VirtualHost *:80>
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
EOF

# Test Apache configuration
if apachectl -t; then
  log "Apache configuration test passed"
else
  log "ERROR: Apache configuration test failed"
  exit 1
fi

# Configure Apache
echo "ServerName $MY_DOMAIN" >> /etc/apache2/apache2.conf
a2dissite 000-default
a2ensite owncloud.conf

# 6. Configure MariaDB
log "=== CONFIGURING MARIADB ==="
sed -i "/\[mysqld\]/atransaction-isolation = READ-COMMITTED\nperformance_schema = on" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl start mariadb

# Verify MariaDB is running
if ! systemctl is-active --quiet mariadb; then
  log "ERROR: MariaDB failed to start"
  exit 1
fi

mysql -u root -e "
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;"

# Test database connection
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
  log "MariaDB configured successfully"
else
  log "ERROR: MariaDB configuration failed"
  exit 1
fi

# 7. Enable Apache modules and restart
log "=== ENABLING APACHE MODULES ==="
a2enmod dir env headers mime rewrite setenvif php8.1
systemctl restart apache2

# Verify Apache is running
if ! systemctl is-active --quiet apache2; then
  log "ERROR: Apache2 failed to start"
  exit 1
fi

log "Apache2 configured and running successfully"

# 8. Download and install OwnCloud
log "=== DOWNLOADING AND INSTALLING OWNCLOUD ==="
cd /var/www/

# Download OwnCloud with error checking
if ! wget -q https://download.owncloud.com/server/stable/owncloud-complete-latest.tar.bz2; then
  log "ERROR: Failed to download OwnCloud"
  exit 1
fi

if ! tar -xjf owncloud-complete-latest.tar.bz2; then
  log "ERROR: Failed to extract OwnCloud"
  exit 1
fi

chown -R www-data. owncloud

# Install OwnCloud with error checking
if ! occ maintenance:install \
--database "mysql" \
--database-name "$DB_NAME" \
--database-user "$DB_USER" \
--database-pass "$DB_PASS" \
--data-dir "/var/www/owncloud/data" \
--admin-user "$ADMIN_USER" \
--admin-pass "$ADMIN_PASS"; then
  log "ERROR: OwnCloud installation failed"
  exit 1
fi

# Configure trusted domains
MY_IP=$(hostname -I | cut -f1 -d ' ')
occ config:system:set trusted_domains 1 --value="$MY_IP"
occ config:system:set trusted_domains 2 --value="$MY_DOMAIN"

log "OwnCloud installed successfully"
log "Access URL: http://$MY_IP"
log "Access URL: http://$MY_DOMAIN"

# 9. Configure background jobs and cron
log "=== CONFIGURING BACKGROUND JOBS ==="
occ background:cron

# Setup cron jobs
echo "*/15  *  *  *  * /var/www/owncloud/occ system:cron" | sudo -u www-data crontab -
echo "0  2  *  *  * /var/www/owncloud/occ dav:cleanup-chunks" | sudo -u www-data crontab -

# 10. Configure cache and locks
log "=== CONFIGURING CACHE AND LOCKS ==="
occ config:system:set memcache.local --value '\OC\Memcache\APCu'
occ config:system:set memcache.locking --value '\OC\Memcache\Redis'
occ config:system:set redis --value '{"host": "127.0.0.1", "port": "6379"}' --type json

# 11. Configure log rotation
log "=== CONFIGURING LOG ROTATION ==="
cat > /etc/logrotate.d/owncloud << 'EOF'
/var/www/owncloud/data/owncloud.log {
  size 10M
  rotate 12
  copytruncate
  missingok
  compress
  compresscmd /bin/gzip
}
EOF

# 12. Configure Samba
log "=== CONFIGURING SAMBA ==="
log "Samba version: $(samba --version)"

# Create Samba configuration
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
if ! adduser --disabled-password --gecos "" "$SAMBA_USER"; then
  log "WARNING: User $SAMBA_USER may already exist"
fi

echo "$SAMBA_USER:$SAMBA_PASS" | chpasswd
echo -e "$SAMBA_PASS\n$SAMBA_PASS" | smbpasswd -a "$SAMBA_USER"

mkdir -p "/home/$SAMBA_USER/pasta_grupo6"
chown "$SAMBA_USER:$SAMBA_USER" "/home/$SAMBA_USER/pasta_grupo6"

systemctl restart smbd

# Verify Samba is running
if ! systemctl is-active --quiet smbd; then
  log "ERROR: Samba failed to start"
  exit 1
fi

log "Samba configured successfully"

# 13. Configure UFW Firewall
log "=== CONFIGURING FIREWALL ==="
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 445/tcp   # Samba
ufw allow 5666/tcp  # NRPE
ufw --force enable

# 14. Install and configure NRPE
log "=== INSTALLING NRPE FROM SOURCE ==="
cd /tmp

# Download NRPE with error checking
if ! wget -q https://github.com/NagiosEnterprises/nrpe/archive/nrpe-4.1.0.tar.gz; then
  log "ERROR: Failed to download NRPE"
  exit 1
fi

if ! tar xzf nrpe-4.1.0.tar.gz; then
  log "ERROR: Failed to extract NRPE"
  exit 1
fi

cd nrpe-nrpe-4.1.0

# Compile and install NRPE
if ! ./configure --enable-command-args; then
  log "ERROR: NRPE configure failed"
  exit 1
fi

if ! make all; then
  log "ERROR: NRPE compilation failed"
  exit 1
fi

make install-groups-users
make install
make install-config
make install-init

systemctl enable nrpe

# Create necessary directories
mkdir -p /usr/local/nagios/var
chown nagios:nagios /usr/local/nagios/var

log "NRPE compiled and installed successfully"

# 15. Deploy NRPE config
log "=== DEPLOYING NRPE CONFIG ==="
NRPE_SRC="${CONF_DIR}/server02_nrpe.cfg"
NRPE_DEST="/usr/local/nagios/etc/nrpe.cfg"

if [[ ! -f "$NRPE_SRC" ]]; then
  log "ERROR: missing NRPE config: $NRPE_SRC"
  exit 1
fi

cp "$NRPE_SRC" "$NRPE_DEST"
chown nagios:nagios "$NRPE_DEST"
chmod 640 "$NRPE_DEST"

# 16. Deploy custom monitoring scripts
log "=== DEPLOYING CUSTOM MONITORING SCRIPTS ==="

# Deploy monitoring scripts from scripts directory
for plugin in check_service_cpu.sh check_locks.sh check_smb_share; do
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

# Also copy check_smb_share to the standard nagios plugins directory for compatibility
cp "${SCRIPTS_DIR}/check_smb_share" "/usr/lib/nagios/plugins/check_smb_share"
chmod +x "/usr/lib/nagios/plugins/check_smb_share"

log "Custom monitoring scripts deployed successfully"

# 17. Configure Fail2Ban
log "=== CONFIGURING FAIL2BAN ==="

# Return to script directory
cd "$SCRIPT_DIR"

# Deploy custom filters from conf directory
OWNCLOUD_FILTER_SRC="${CONF_DIR}/server02_owncloud-auth.conf"
SAMBA_FILTER_SRC="${CONF_DIR}/server02_samba-auth.conf"

if [[ ! -f "$OWNCLOUD_FILTER_SRC" ]]; then
  log "ERROR: missing OwnCloud filter: $OWNCLOUD_FILTER_SRC"
  exit 1
fi

if [[ ! -f "$SAMBA_FILTER_SRC" ]]; then
  log "ERROR: missing Samba filter: $SAMBA_FILTER_SRC"
  exit 1
fi

# Copy filter files
cp "$OWNCLOUD_FILTER_SRC" /etc/fail2ban/filter.d/owncloud-auth.conf
cp "$SAMBA_FILTER_SRC" /etc/fail2ban/filter.d/samba-auth.conf
chmod 644 /etc/fail2ban/filter.d/owncloud-auth.conf
chmod 644 /etc/fail2ban/filter.d/samba-auth.conf

log "Fail2Ban filters deployed successfully"

# Deploy Fail2Ban configuration
FAIL2BAN_SRC="${CONF_DIR}/server02_fail2ban_jail_local.conf"

if [[ ! -f "$FAIL2BAN_SRC" ]]; then
  log "ERROR: missing Fail2Ban config: $FAIL2BAN_SRC"
  exit 1
fi

mkdir -p /etc/fail2ban
if [[ -f "/etc/fail2ban/jail.local" ]]; then
  rm -f /etc/fail2ban/jail.local
fi

if cp "$FAIL2BAN_SRC" /etc/fail2ban/jail.local; then
  chmod 644 /etc/fail2ban/jail.local
  log "Fail2Ban configuration deployed successfully"
else
  log "ERROR: Failed to copy Fail2Ban configuration"
  exit 1
fi

# 18. Enable and restart services
log "=== ENABLING AND RESTARTING SERVICES ==="
systemctl enable apache2 mariadb redis-server smbd nrpe fail2ban
systemctl restart apache2 mariadb redis-server smbd nrpe fail2ban

# 19. Final setup
log "=== FINALIZING SETUP ==="
cd /var/www/
chown -R www-data. owncloud

# 20. Verify services status
log "=== CHECKING SERVICES STATUS ==="

services=("apache2" "mariadb" "redis-server" "smbd" "nrpe" "fail2ban")
failed_services=()

for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    log "$service is running"
  else
    log "ERROR: $service is not running"
    failed_services+=("$service")
  fi
done

# Report any failed services
if [ ${#failed_services[@]} -gt 0 ]; then
  log "WARNING: The following services failed to start: ${failed_services[*]}"
  log "Please check the logs for these services"
else
  log "All services are running successfully"
fi

# Test NRPE connection
if command -v /usr/local/nagios/libexec/check_nrpe &>/dev/null; then
  log "Testing NRPE connection..."
  if /usr/local/nagios/libexec/check_nrpe -H localhost; then
    log "NRPE connection test successful"
  else
    log "WARNING: NRPE connection test failed"
  fi
else
  log "NRPE check command not found"
fi

# Check Fail2Ban jails
if command -v fail2ban-client &>/dev/null; then
  log "Fail2Ban status:"
  fail2ban-client status
else
  log "fail2ban-client not found"
fi

# Display OwnCloud version
if command -v occ &>/dev/null; then
  log "OwnCloud version: $(occ -V)"
else
  log "OCC command not found"
fi

log "=== SERVER 2 CONFIGURATION COMPLETED SUCCESSFULLY ==="
log "OwnCloud is accessible at: http://$MY_IP"
log "OwnCloud is accessible at: http://$MY_DOMAIN"
log "Admin user: $ADMIN_USER"
log "Samba share: \\\\$MY_IP\\grupo6"
log "Check output_sv2.txt for detailed logs" 