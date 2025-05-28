#!/usr/bin/env bash

# ===============================
# Server 2 Configuration Script (deploy_sv2.sh)
# Installs and configures OwnCloud + MariaDB
# Based on raw_server2.sh commands and official documentation
# ===============================

# Função para log com timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a output_sv2.txt
}

# Redirecionar toda a saída para output_sv2.txt e também para o terminal
exec > >(tee -a output_sv2.txt)
exec 2>&1

log "=== INICIANDO INSTALAÇÃO OWNCLOUD + MARIADB ==="

# Ensure script is run as root
if [[ $(id -u) -ne 0 ]]; then
  log "ERROR: This script must be run as root."
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
log "Updating system packages..."
apt update && apt upgrade -y

# Cria um OCC Script Helper
log "Creating OCC helper script..."
FILE="/usr/local/bin/occ"
cat <<EOM >$FILE
#! /bin/bash
cd /var/www/owncloud
sudo -E -u www-data /usr/bin/php /var/www/owncloud/occ "\$@"
EOM

# Faz o script executavel
chmod +x $FILE
log "OCC script helper created at $FILE"

# Instala os packages necessários
log "Adding ondrej/php PPA repository..."
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update && sudo apt upgrade

log "Installing required packages..."
apt install -y \
  apache2 \
  libapache2-mod-php7.4 \
  mariadb-server openssl redis-server wget \
  php7.4 php7.4-imagick php7.4-common php7.4-curl \
  php7.4-gd php7.4-imap php7.4-intl php7.4-json \
  php7.4-mbstring php7.4-gmp php7.4-bcmath php7.4-mysql \
  php7.4-ssh2 php7.4-xml php7.4-zip php7.4-apcu \
  php7.4-redis php7.4-ldap php-phpseclib

if [ $? -eq 0 ]; then
  log "Required packages installed successfully"
else
  log "ERROR: Failed to install required packages"
  exit 1
fi

# Instala o SMBClient PHP Module
log "Installing SMBClient PHP module..."
apt-get install -y php7.4-smbclient
echo "extension=smbclient.so" > /etc/php/7.4/mods-available/smbclient.ini
phpenmod smbclient
systemctl restart apache2

# Verifica se foi ativado com sucesso
log "Verifying SMBClient installation..."
if php -m | grep smbclient; then
  log "SMBClient PHP module installed successfully"
else
  log "WARNING: SMBClient module may not be properly installed"
fi

# Instala pacotes recomendados pelo owncloud
log "Installing recommended packages..."
apt install -y \
  unzip bzip2 rsync curl jq \
  inetutils-ping  ldap-utils\
  smbclient

log "Recommended packages installed"

# Configuração do Apache2
log "Configuring Apache2 Virtual Host..."

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

log "Apache virtual host configuration created"

# Testa a configuração
log "Testing Apache configuration..."
apachectl -t

# Insere o domain name na configuração do apache
echo "ServerName $my_domain" >> /etc/apache2/apache2.conf
log "ServerName added to Apache configuration"

# Habilita a configuração Virtual Host
log "Enabling virtual host..."
a2dissite 000-default
a2ensite owncloud.conf

# Configuração de base de dados MariaDB
log "Configuring MariaDB..."
sed -i "/\[mysqld\]/atransaction-isolation = READ-COMMITTED\nperformance_schema = on" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl start mariadb

log "Creating OwnCloud database and user..."
mysql -u root -e \
"CREATE DATABASE IF NOT EXISTS owncloud; \
CREATE USER IF NOT EXISTS 'owncloud'@'localhost' IDENTIFIED BY 'OwncloudDB#password123'; \
GRANT ALL PRIVILEGES ON owncloud.* TO 'owncloud'@'localhost' WITH GRANT OPTION; \
FLUSH PRIVILEGES;"

if [ $? -eq 0 ]; then
  log "MariaDB database and user created successfully"
else
  log "ERROR: Failed to create database and user"
  exit 1
fi

# Habilita modulos Apache recomendados e reinicia o serviço
log "Enabling Apache modules..."
a2enmod dir env headers mime rewrite setenvif
systemctl restart apache2

log "Apache modules enabled and service restarted"

# Download Owncload
log "Downloading OwnCloud..."
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

# Instalação Owncload
log "Installing OwnCloud..."
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

# Configura os dominios confiáveis (Trusted Domains)
log "Configuring trusted domains..."
my_ip=$(hostname -I|cut -f1 -d ' ')
occ config:system:set trusted_domains 1 --value="$my_ip"
occ config:system:set trusted_domains 2 --value="$my_domain"

log "Trusted domains configured: $my_ip and $my_domain"

# Define o cron job para modo background
log "Configuring background jobs..."
occ background:cron

# Define a execução do cronjon para a cada 15 minutos e elimina os chuncks todas as noites às 02:00H
echo "*/15  *  *  *  * /var/www/owncloud/occ system:cron" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
echo "0  2  *  *  * /var/www/owncloud/occ dav:cleanup-chunks" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
  
log "Cron jobs configured"

# Configura Cache e Locks de ficheiros
log "Configuring cache and file locking..."
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

log "Cache and file locking configured"

# Configura rotação de logs
log "Configuring log rotation..."
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

# Verificação final
log "Verifying installation..."
occ -V
echo "Your ownCloud is accessable under: "$my_ip
echo "Your ownCloud is accessable under: "$my_domain
echo "The Installation is complete."

log "=== OWNCLOUD + MARIADB INSTALLATION COMPLETED ==="
log "OwnCloud Admin: admin / OwnCloud#server2_password123"
log "Database: owncloud / OwncloudDB#password123"
log "OwnCloud URL: http://$my_ip"
log "OwnCloud URL: http://$my_domain"
