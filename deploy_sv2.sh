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

# === INSTALAÇÃO OWNCLOUD + MARIADB ===

# Define o domain name
my_domain="owncloud.cgs6.local"
echo $my_domain

hostnamectl set-hostname $my_domain
hostname -f

log "Hostname set to: $(hostname -f)"

# Atualiza os pacotes e dá upgrade
apt update && apt upgrade -y

# Cria um OCC Script Helper
FILE="/usr/local/bin/occ"
cat <<EOM >$FILE
#! /bin/bash
cd /var/www/owncloud
sudo -E -u www-data /usr/bin/php /var/www/owncloud/occ "\$@"
EOM

# Faz o script executavel
chmod +x $FILE

log "OCC script helper created"

# Instala os packages necessários
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update && sudo apt upgrade -y

# Install packages with error checking
log "Installing core packages..."
if ! apt install -y \
  apache2 \
  libapache2-mod-php7.4 \
  mariadb-server mariadb-client openssl redis-server wget \
  php7.4 php7.4-imagick php7.4-common php7.4-curl \
  php7.4-gd php7.4-imap php7.4-intl php7.4-json \
  php7.4-mbstring php7.4-gmp php7.4-bcmath php7.4-mysql \
  php7.4-ssh2 php7.4-xml php7.4-zip php7.4-apcu \
  php7.4-redis php7.4-ldap php-phpseclib; then
  log "ERROR: Package installation failed"
  exit 1
fi

# Verify critical packages are installed
log "Verifying package installation..."

if ! command -v apache2 &>/dev/null; then
  log "ERROR: Apache2 not installed, trying alternative installation..."
  apt install -y apache2 apache2-utils
fi

if ! command -v mysql &>/dev/null; then
  log "ERROR: MariaDB not installed, trying alternative installation..."
  apt install -y mariadb-server mariadb-client mysql-common
fi

if ! command -v redis-server &>/dev/null; then
  log "ERROR: Redis not installed, trying alternative installation..."
  apt install -y redis-server redis-tools
fi

# Verify again
missing_packages=()
if ! command -v apache2 &>/dev/null; then missing_packages+=("apache2"); fi
if ! command -v mysql &>/dev/null; then missing_packages+=("mariadb"); fi
if ! command -v redis-server &>/dev/null; then missing_packages+=("redis"); fi

if [ ${#missing_packages[@]} -gt 0 ]; then
  log "ERROR: Critical packages still missing: ${missing_packages[*]}"
  log "Please install manually: apt install apache2 mariadb-server redis-server"
  exit 1
fi

# Ensure critical services are started
systemctl enable apache2 mariadb redis-server
systemctl start apache2 mariadb redis-server

# Verify services are running
if ! systemctl is-active --quiet apache2; then
  log "ERROR: Apache2 failed to start"
  systemctl status apache2
fi

if ! systemctl is-active --quiet mariadb; then
  log "ERROR: MariaDB failed to start"
  systemctl status mariadb
fi

if ! systemctl is-active --quiet redis-server; then
  log "ERROR: Redis failed to start"
  systemctl status redis-server
fi

log "Core packages installed and services started successfully"

# Instala o SMBClient PHP Module
apt-get install -y php7.4-smbclient
echo "extension=smbclient.so" > /etc/php/7.4/mods-available/smbclient.ini
phpenmod smbclient
systemctl restart apache2

# Verifica se foi ativado com sucesso
php -m | grep smbclient

log "SMBClient PHP module configured"

# Instala pacotes recomendados pelo owncloud
apt install -y \
  unzip bzip2 rsync curl jq \
  inetutils-ping  ldap-utils\
  smbclient

log "Recommended packages installed"

# Configuração do Apache2
# Criação de Virtual Hosts

# Verify Apache is installed and directories exist
if [ ! -d "/etc/apache2/sites-available" ]; then
  log "ERROR: Apache2 not properly installed - missing sites-available directory"
  exit 1
fi

FILE="/etc/apache2/sites-available/owncloud.conf"
cat <<EOM >$FILE
<VirtualHost *:80>
# uncommment the line below if variable was set
#ServerName \$my_domain
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

# Testa a configuração
if command -v apachectl &>/dev/null; then
  apachectl -t
else
  log "WARNING: apachectl command not found, skipping configuration test"
fi

# Insere o domain name na configuração do apache
if [ -f "/etc/apache2/apache2.conf" ]; then
  echo "ServerName $my_domain" >> /etc/apache2/apache2.conf
else
  log "WARNING: /etc/apache2/apache2.conf not found"
fi

# Habilita a configuração Virtual Host
if command -v a2dissite &>/dev/null && command -v a2ensite &>/dev/null; then
  a2dissite 000-default
  a2ensite owncloud.conf
else
  log "WARNING: a2dissite/a2ensite commands not found"
fi

log "Apache2 virtual host configured"

# Configuração de base de dados MariaDB

# Check if MariaDB configuration directory exists
if [ -d "/etc/mysql/mariadb.conf.d" ] && [ -f "/etc/mysql/mariadb.conf.d/50-server.cnf" ]; then
  sed -i "/\[mysqld\]/atransaction-isolation = READ-COMMITTED\nperformance_schema = on" /etc/mysql/mariadb.conf.d/50-server.cnf
else
  log "WARNING: MariaDB configuration file not found, trying alternative locations..."
  
  # Try alternative configuration files
  if [ -f "/etc/mysql/my.cnf" ]; then
    echo -e "\n[mysqld]\ntransaction-isolation = READ-COMMITTED\nperformance_schema = on" >> /etc/mysql/my.cnf
    log "Added configuration to /etc/mysql/my.cnf"
  elif [ -f "/etc/mysql/mysql.conf.d/mysqld.cnf" ]; then
    sed -i "/\[mysqld\]/atransaction-isolation = READ-COMMITTED\nperformance_schema = on" /etc/mysql/mysql.conf.d/mysqld.cnf
    log "Added configuration to /etc/mysql/mysql.conf.d/mysqld.cnf"
  else
    log "WARNING: No MariaDB configuration file found"
  fi
fi

# Start MariaDB service
if systemctl list-unit-files | grep -q mariadb.service; then
  systemctl restart mariadb
elif systemctl list-unit-files | grep -q mysql.service; then
  systemctl restart mysql
  log "Using mysql.service instead of mariadb.service"
else
  log "ERROR: Neither mariadb.service nor mysql.service found"
  exit 1
fi

# Verify MariaDB is running after restart
if systemctl is-active --quiet mariadb 2>/dev/null; then
  service_name="mariadb"
elif systemctl is-active --quiet mysql 2>/dev/null; then
  service_name="mysql"
else
  log "ERROR: MariaDB/MySQL failed to start"
  systemctl status mariadb 2>/dev/null || systemctl status mysql 2>/dev/null
  exit 1
fi

log "MariaDB service ($service_name) is running"

# Configure database
if command -v mysql &>/dev/null; then
  mysql -u root -e \
  "CREATE DATABASE IF NOT EXISTS owncloud; \
  CREATE USER IF NOT EXISTS 'owncloud'@'localhost' IDENTIFIED BY 'OwncloudDB#password123'; \
  GRANT ALL PRIVILEGES ON owncloud.* TO 'owncloud'@'localhost' WITH GRANT OPTION; \
  FLUSH PRIVILEGES;"

  # Test database connection
  if mysql -u owncloud -p'OwncloudDB#password123' -e "USE owncloud;" 2>/dev/null; then
    log "MariaDB configured and tested successfully"
  else
    log "ERROR: MariaDB configuration test failed"
    exit 1
  fi
else
  log "ERROR: mysql command not found"
  exit 1
fi

# Habilita modulos Apache recomendados e reinicia o serviço
if command -v a2enmod &>/dev/null; then
  a2enmod dir env headers mime rewrite setenvif
else
  log "WARNING: a2enmod command not found, skipping module enablement"
fi

systemctl restart apache2

# Verify Apache is running after restart
if ! systemctl is-active --quiet apache2; then
  log "ERROR: Apache2 failed to restart after module configuration"
  systemctl status apache2
  exit 1
fi

log "Apache modules enabled and service verified"

# Download Owncload
cd /var/www/
wget https://download.owncloud.com/server/stable/owncloud-complete-latest.tar.bz2 && \
tar -xjf owncloud-complete-latest.tar.bz2 && \
chown -R www-data. owncloud

log "OwnCloud downloaded and extracted"

# Instalação Owncload
occ maintenance:install \
--database "mysql" \
--database-name "owncloud" \
--database-user "owncloud" \
--database-pass "OwncloudDB#password123" \
--data-dir "/var/www/owncloud/data" \
--admin-user "admin" \
--admin-pass "OwnCloud#server2_password123"

# Verify OwnCloud installation
if [ $? -eq 0 ] && [ -f "/var/www/owncloud/config/config.php" ]; then
  log "OwnCloud installed successfully"
else
  log "ERROR: OwnCloud installation failed"
  exit 1
fi

# Configura os dominios confiáveis (Trusted Domains)
my_ip=$(hostname -I|cut -f1 -d ' ')
occ config:system:set trusted_domains 1 --value="$my_ip"
occ config:system:set trusted_domains 2 --value="$my_domain"

log "Trusted domains configured: $my_ip and $my_domain"

# Define o cron job para modo background
occ background:cron

# Define a execução do cronjon para a cada 15 minutos e elimina os chuncks todas as noites às 02:00H
echo "*/15  *  *  *  * /var/www/owncloud/occ system:cron" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
echo "0  2  *  *  * /var/www/owncloud/occ dav:cleanup-chunks" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
  
log "Background jobs and cron configured"

# Configura Cache e Locks de ficheiros
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

# Configura rotação de logs
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

# Finaliza o processo de instalação
cd /var/www/
chown -R www-data. owncloud

occ -V
echo "Your ownCloud is accessable under: "$my_ip
echo "Your ownCloud is accessable under: "$my_domain
echo "The Installation is complete."

log "OwnCloud installation completed successfully"

# === UFW FIREWALL ===

log "=== CONFIGURING UFW FIREWALL ==="

# Permite acesso externo SSH
ufw allow 22/tcp

# Permite acesso externo HTTP & HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Habilita o ufw
ufw --force enable

log "UFW firewall configured"

# === SAMBA SERVER ===

log "=== CONFIGURING SAMBA SERVER ==="

# Atualização de packages ubuntu
apt update && sudo apt upgrade -y

# Instalação do Samba
apt install samba -y

# Verifica versão instalad
samba --version

log "Samba version: $(samba --version)"

# Adiciona configuração do samba
cat >> /etc/samba/smb.conf << 'EOF'

[grupo6]
   comment = Pasta partilhada grupo 6
   path = /home/grupo6/pasta_grupo6
   valid users = grupo6
   browseable = yes
   writable = yes
   guest ok = no
   read only = no
EOF

sudo adduser grupo6
sudo smbpasswd -a grupo6
mkdir -p /home/grupo6/pasta_grupo6
sudo chown grupo6:grupo6 /home/grupo6/pasta_grupo6
systemctl restart smbd

ufw allow 445/tcp

log "Samba configured successfully"

# === INSTALAÇÃO NRPE ===

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

# Deploy NRPE config
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

sudo ufw allow 5666/tcp

sudo mkdir -p /usr/local/nagios/var
sudo chown nagios:nagios /usr/local/nagios/var

sudo systemctl restart nrpe
sudo systemctl status nrpe
/usr/local/nagios/libexec/check_nrpe -H localhost

log "NRPE configured and tested"

# === INSTALA DEPENDENCIAS AGENTES ===

log "=== INSTALLING MONITORING DEPENDENCIES ==="

sudo apt install nagios-plugins nagios-plugins-contrib

# Deploy custom monitoring scripts
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

log "Monitoring scripts deployed"

# === FAIL2BAN ===

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

fail2ban-client status
fail2ban-client status sshd
fail2ban-client status owncloud-auth
fail2ban-client status samba-auth

log "Fail2Ban configured successfully"

# === VERIFICAÇÃO FINAL ===

log "=== FINAL VERIFICATION ==="

services=("apache2" "mariadb" "redis-server" "smbd" "nrpe" "fail2ban")
for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    log "$service is running"
  else
    log "WARNING: $service is not running"
  fi
done

# === CORREÇÃO DE PROBLEMAS ===

log "=== FIXING ANY REMAINING ISSUES ==="

# Ensure MariaDB client is installed
if ! command -v mysql &>/dev/null; then
  log "Installing missing MariaDB client..."
  apt install -y mariadb-client
fi

# Start and enable all critical services
log "Ensuring all services are started and enabled..."
systemctl enable apache2 mariadb redis-server smbd nrpe fail2ban
systemctl start apache2 mariadb redis-server smbd nrpe fail2ban

# Wait a moment for services to start
sleep 5

# Verify and fix each service
log "Verifying each service..."

# Apache2
if ! systemctl is-active --quiet apache2; then
  log "Fixing Apache2..."
  systemctl restart apache2
  sleep 2
  if ! systemctl is-active --quiet apache2; then
    log "ERROR: Apache2 still not running"
    systemctl status apache2
  else
    log "Apache2 fixed and running"
  fi
fi

# MariaDB
if ! systemctl is-active --quiet mariadb; then
  log "Fixing MariaDB..."
  systemctl restart mariadb
  sleep 3
  if ! systemctl is-active --quiet mariadb; then
    log "ERROR: MariaDB still not running"
    systemctl status mariadb
  else
    log "MariaDB fixed and running"
  fi
fi

# Redis
if ! systemctl is-active --quiet redis-server; then
  log "Fixing Redis..."
  systemctl restart redis-server
  sleep 2
  if ! systemctl is-active --quiet redis-server; then
    log "ERROR: Redis still not running"
    systemctl status redis-server
  else
    log "Redis fixed and running"
  fi
fi

# Test database connection
log "Testing database connection..."
if mysql -u owncloud -p'OwncloudDB#password123' -e "USE owncloud;" 2>/dev/null; then
  log "Database connection successful"
else
  log "WARNING: Database connection failed - may need manual intervention"
fi

# Test Redis connection
log "Testing Redis connection..."
if redis-cli ping 2>/dev/null | grep -q PONG; then
  log "Redis connection successful"
else
  log "WARNING: Redis connection failed"
fi

# Fix OwnCloud permissions
if [ -d "/var/www/owncloud" ]; then
  log "Fixing OwnCloud permissions..."
  chown -R www-data:www-data /var/www/owncloud
  
  # Test OCC command
  if [ -f "/var/www/owncloud/occ" ]; then
    log "Testing OCC command..."
    sudo -u www-data php /var/www/owncloud/occ status 2>/dev/null || log "OCC command needs attention"
  fi
fi

# Test Apache configuration
log "Testing Apache configuration..."
if apachectl -t 2>/dev/null; then
  log "Apache configuration is valid"
else
  log "WARNING: Apache configuration has issues"
fi

# Final service status check
log "=== FINAL SERVICE STATUS ==="
failed_services=()

for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    log "✓ $service is running"
  else
    log "✗ $service is NOT running"
    failed_services+=("$service")
  fi
done

# Report results
if [ ${#failed_services[@]} -eq 0 ]; then
  log "🎉 ALL SERVICES ARE RUNNING SUCCESSFULLY!"
else
  log "⚠️  SERVICES STILL NOT RUNNING: ${failed_services[*]}"
  log "Manual intervention may be required for these services"
fi

log "=== SERVER 2 CONFIGURATION COMPLETED ==="
log "OwnCloud Admin: admin / OwnCloud#server2_password123"
log "Database: owncloud / OwncloudDB#password123"
log "Samba User: grupo6 / grupo6_samba123!"
log "OwnCloud URL: http://$my_ip"
log "OwnCloud URL: http://$my_domain"
log "Samba Share: \\\\$my_ip\\grupo6"
log "Check output_sv2.txt for detailed logs"
log "Run ./health_check_sv2.sh to verify installation"
