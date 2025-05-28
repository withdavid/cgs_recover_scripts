#!/usr/bin/env bash

# ===============================
# Server 3 Configuration Script (deploy_sv3.sh)
# Installs and configures Nagios Core monitoring server
# Based on raw_server3.sh commands
# ===============================

# Função para log com timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a output_sv3.txt
}

# Redirecionar toda a saída para output_sv3.txt e também para o terminal
exec > >(tee -a output_sv3.txt)
exec 2>&1

log "=== INICIANDO INSTALAÇÃO NAGIOS CORE SERVER ==="

# Ensure script is run as root
if [[ $(id -u) -ne 0 ]]; then
  log "ERROR: This script must be run as root."
  exit 1
fi

# Determine script and config directories
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONF_DIR="${SCRIPT_DIR}/conf"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Check config directories
if [[ ! -d "$CONF_DIR" ]]; then
  log "ERROR: Config directory not found: $CONF_DIR"
  exit 1
fi

log "Using config directory: $CONF_DIR"

# === INSTALAÇÃO NAGIOS CORE ===

log "=== INSTALLING NAGIOS CORE ==="

# Instala dependências
log "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y autoconf gcc libc6 make wget unzip apache2 php libapache2-mod-php libgd-dev ufw
sudo apt-get install -y openssl libssl-dev

if [ $? -eq 0 ]; then
  log "Dependencies installed successfully"
else
  log "ERROR: Failed to install dependencies"
  exit 1
fi

# Download e compilação do Nagios Core
log "Downloading Nagios Core..."
cd /tmp
wget -O nagioscore.tar.gz $(wget -q -O - https://api.github.com/repos/NagiosEnterprises/nagioscore/releases/latest  | grep '"browser_download_url":' | grep -o 'https://[^"]*')

if [ $? -eq 0 ]; then
  log "Nagios Core downloaded successfully"
else
  log "ERROR: Failed to download Nagios Core"
  exit 1
fi

tar xzf nagioscore.tar.gz
cd /tmp/nagios-*

log "Configuring Nagios Core..."
sudo ./configure --with-httpd-conf=/etc/apache2/sites-enabled

if [ $? -eq 0 ]; then
  log "Nagios Core configured successfully"
else
  log "ERROR: Failed to configure Nagios Core"
  exit 1
fi

log "Compiling Nagios Core..."
sudo make all

if [ $? -eq 0 ]; then
  log "Nagios Core compiled successfully"
else
  log "ERROR: Failed to compile Nagios Core"
  exit 1
fi

# Instalação do Nagios
log "Installing Nagios Core..."
sudo make install-groups-users
sudo usermod -a -G nagios www-data

sudo make install
sudo make install-daemoninit
sudo make install-commandmode
sudo make install-config
sudo make install-webconf

log "Nagios Core installed successfully"

# Configuração do Apache
log "Configuring Apache..."
sudo a2enmod rewrite
sudo a2enmod cgi

sudo ufw allow Apache
sudo ufw reload

# Criação do usuário web do Nagios
log "Creating Nagios web user..."
echo "Please enter password for nagiosadmin user:"
sudo htpasswd -c /usr/local/nagios/etc/htpasswd.users nagiosadmin

sudo systemctl restart apache2.service
sudo systemctl start nagios.service

log "Apache and Nagios services started"

# === INSTALAÇÃO PLUGINS ESSENCIAIS NAGIOS ===

log "=== INSTALLING NAGIOS PLUGINS ==="

# Instala dependências dos plugins
log "Installing plugin dependencies..."
sudo apt-get install -y autoconf gcc libc6 libmcrypt-dev make libssl-dev wget bc gawk dc build-essential snmp libnet-snmp-perl gettext

# Download e compilação dos plugins
log "Downloading Nagios plugins..."
cd /tmp
wget -O nagios-plugins.tar.gz $(wget -q -O - https://api.github.com/repos/nagios-plugins/nagios-plugins/releases/latest  | grep '"browser_download_url":' | grep -o 'https://[^"]*')

if [ $? -eq 0 ]; then
  log "Nagios plugins downloaded successfully"
else
  log "ERROR: Failed to download Nagios plugins"
  exit 1
fi

tar zxf nagios-plugins.tar.gz
cd /tmp/nagios-plugins-*/

log "Configuring and compiling Nagios plugins..."
sudo ./configure
sudo make
sudo make install

if [ $? -eq 0 ]; then
  log "Nagios plugins installed successfully"
else
  log "ERROR: Failed to install Nagios plugins"
  exit 1
fi

# Reinicia serviços
log "Restarting Nagios services..."
sudo systemctl start nagios.service
sudo systemctl stop nagios.service
sudo systemctl restart nagios.service
sudo systemctl status nagios.service

# === CONFIGURAÇÃO DOS HOSTS ===

log "=== CONFIGURING NAGIOS HOSTS ==="

# Configuração de hosts
log "Creating hosts configuration..."
cat > /usr/local/nagios/etc/objects/hosts.cfg << 'EOF'
define host{
    use             linux-server
    host_name       sv01-web.cgs6.local
    alias           Servidor 1 (WEB)
    address         10.101.150.66
    contact_groups  admins, equipa_sv01
}

define host{
    use             linux-server
    host_name       sv02-owncloud.cgs6.local
    alias           Servidor 2 (Owncloud)
    address         10.101.150.67
    contact_groups  admins, equipa_sv02
}
EOF

log "Hosts configuration created"

# === CONFIGURAÇÃO DOS COMANDOS ===

log "=== CONFIGURING NAGIOS COMMANDS ==="

# Backup do arquivo original
cp /usr/local/nagios/etc/objects/commands.cfg /usr/local/nagios/etc/objects/commands.cfg.backup

# Adiciona comando check_nrpe no início do arquivo
log "Adding check_nrpe command..."
sed -i '/^# COMMANDS.CFG/a\\n# COMANDOS ALTERADO POR NOS\n\ndefine command{\n    command_name    check_nrpe\n    command_line    /usr/lib/nagios/plugins/check_nrpe -H $HOSTADDRESS$ -c $ARG1$\n}' /usr/local/nagios/etc/objects/commands.cfg

log "Commands configuration updated"

# === CONFIGURAÇÃO DOS SERVIÇOS ===

log "=== CONFIGURING NAGIOS SERVICES ==="

# Configuração de serviços
log "Creating services configuration..."
cat > /usr/local/nagios/etc/objects/services.cfg << 'EOF'
### Serviços de Servidor 1 (sv01-web.cgs6.local)

## VM Resources

# Check CPU load
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     CPU Utilization
    check_command           check_nrpe!check_cpu
    contact_groups          equipa_sv01
}

# Check Mem load
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     Memory Utilization
    check_command           check_nrpe!check_mem
    contact_groups          equipa_sv01
}

# Check disk usage
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     Disk Usage
    check_command           check_nrpe!check_disk_root
    contact_groups          equipa_sv01
}

# check SWAP usage
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     Swap Usage
    check_command           check_nrpe!check_swap
    contact_groups          equipa_sv01
}

# Check network erros
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     Network Errors
    check_command           check_nrpe!check_net_err
    contact_groups          equipa_sv01
}

## SERVICES

# NGINX
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     Nginx Web Server
    check_command           check_nrpe!check_nginx
    contact_groups          equipa_sv01
}

# DNS Server
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     DNS Server
    check_command           check_nrpe!check_dns
    contact_groups          equipa_sv01
}

# POSIX
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     POSIX Lock Monitor
    check_command           check_nrpe!check_posix_locks
    contact_groups          equipa_sv01
}

# FLOCK
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     FLOCK Lock Monitor
    check_command           check_nrpe!check_flock_locks
    contact_groups          equipa_sv01
}

### SV01 – Carga CPU de serviços ###
define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     NGINX Load
    check_command           check_nrpe!check_http_cpu
    contact_groups          equipa_sv01
}

define service{
    use                     generic-service
    host_name               sv01-web.cgs6.local
    service_description     DNS Load
    check_command           check_nrpe!check_dns_cpu
    contact_groups          equipa_sv01
}

### Serviços de Servidor 2 (sv02-owncloud.cgs6.local)

## VM Resources

# Check CPU load
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     CPU Utilization
    check_command           check_nrpe!check_cpu
    contact_groups          equipa_sv02
}

# Check Mem load
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     Memory Utilization
    check_command           check_nrpe!check_mem
    contact_groups          equipa_sv02
}

# Check disk usage
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     Disk Usage
    check_command           check_nrpe!check_disk_root
    contact_groups          equipa_sv02
}

# check SWAP usage
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     Swap Usage
    check_command           check_nrpe!check_swap
    contact_groups          equipa_sv02
}

# Check network erros
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     Network Errors
    check_command           check_nrpe!check_net_err
    contact_groups          equipa_sv02
}

##Services

# POSIX
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     POSIX Lock Monitor
    check_command           check_nrpe!check_posix_locks
    contact_groups          equipa_sv02
}

# FLOCK
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     FLOCK Lock Monitor
    check_command           check_nrpe!check_flock_locks
    contact_groups          equipa_sv02
}

# Owncloud HTTP
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     OwnCloud HTTP
    check_command           check_http
    contact_groups          equipa_sv02
}

# SAMBA
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     Samba/CIFS
    check_command           check_nrpe!check_samba
    contact_groups          equipa_sv02
}

# MariaDB
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     MariaDB Connection
    check_command           check_nrpe!check_mariadb
    contact_groups          equipa_sv02
}

### SV02 – Carga CPU de serviços ###
define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     Owncloud HTTP Load
    check_command           check_nrpe!check_http_cpu
    contact_groups          equipa_sv02
}

define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     MySQL Load
    check_command           check_nrpe!check_mysql_cpu
    contact_groups          equipa_sv02
}

define service{
    use                     generic-service
    host_name               sv02-owncloud.cgs6.local
    service_description     Samba Load
    check_command           check_nrpe!check_samba_cpu
    contact_groups          equipa_sv02
}
EOF

log "Services configuration created"

# Validação da configuração
log "Validating Nagios configuration..."
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

if [ $? -eq 0 ]; then
  log "Nagios configuration is valid"
else
  log "ERROR: Nagios configuration validation failed"
  exit 1
fi

sudo systemctl restart nagios

# === CONFIGURAÇÃO DOS CONTATOS ===

log "=== CONFIGURING NAGIOS CONTACTS ==="

# Backup do arquivo original
cp /usr/local/nagios/etc/objects/contacts.cfg /usr/local/nagios/etc/objects/contacts.cfg.backup

# Configuração de contatos
log "Creating contacts configuration..."
cat > /usr/local/nagios/etc/objects/contacts.cfg << 'EOF'
###############################################################################
# CONTACTS.CFG - SAMPLE CONTACT/CONTACTGROUP DEFINITIONS
###############################################################################

###############################################################################
# CONTACTS
###############################################################################

define contact {
    contact_name            nagiosadmin             ; Short name of user
    use                     generic-contact         ; Inherit default values from generic-contact template (defined above)
    alias                   Nagios Admin            ; Full name of user
    email                   admin@cgs6.local        ; Email address
}

define contact {
    contact_name            joao_admin                          ; nome interno (único)
    alias                   João da Equipa Infra                ; nome mais amigável
    service_notification_period  24x7                           ; período durante o qual será notificado
    host_notification_period     24x7
    service_notification_options w,u,c,r                        ; quando notificar (w=warning, u=unknown, etc.)
    host_notification_options    d,u,r                          ; quando notificar (d=down, u=unreachable, etc.)
    service_notification_commands notify-service-by-email
    host_notification_commands    notify-host-by-email
    email                   joao@cgs6.local                     ; email onde receberá alertas
    use                     generic-contact                     ; herda propriedades comuns (opcional)
}

define contact {
    contact_name            maria_admin                         ; nome interno (único)
    alias                   Maria da Equipa NOC                 ; nome mais amigável
    service_notification_period  24x7                           ; período durante o qual será notificado
    host_notification_period     24x7
    service_notification_options w,u,c,r                        ; quando notificar (w=warning, u=unknown, etc.)
    host_notification_options    d,u,r                          ; quando notificar (d=down, u=unreachable, etc.)
    service_notification_commands notify-service-by-email
    host_notification_commands    notify-host-by-email
    email                   maria@cgs6.local                     ; email onde receberá alertas
    use                     generic-contact                     ; herda propriedades comuns (opcional)
}

###############################################################################
# CONTACT GROUPS
###############################################################################

define contactgroup {
    contactgroup_name       admins
    alias                   Nagios Administrators
    members                 nagiosadmin
}

define contactgroup {
    contactgroup_name       equipa_sv01
    alias                   Equipa de Operações do SV01
    members                 joao_admin
}

define contactgroup {
    contactgroup_name       equipa_sv02
    alias                   Equipa de Operações do SV02
    members                 maria_admin
}
EOF

log "Contacts configuration created"

# === CONFIGURAÇÃO DOS GRUPOS DE SERVIÇOS ===

log "=== CONFIGURING SERVICE GROUPS ==="

# Configuração de grupos de serviços
log "Creating service groups configuration..."
cat > /usr/local/nagios/etc/objects/servicegroups.cfg << 'EOF'
###############################################################################
# ServiceGroups for SV01 (sv01-web.cgs6.local)
###############################################################################

define servicegroup{
    servicegroup_name       sv01-vm-resources
    alias                   SV01 VM Resources
    members                 sv01-web.cgs6.local,CPU Utilization,sv01-web.cgs6.local,Memory Utilization,sv01-web.cgs6.local,Disk Usage,sv01-web.cgs6.local,Swap Usage,sv01-web.cgs6.local,Network Errors,sv01-web.cgs6.local,POSIX Lock Monitor,sv01-web.cgs6.local,FLOCK Lock Monitor
}

define servicegroup{
    servicegroup_name       sv01-app-services
    alias                   SV01 Application Services
    members                 sv01-web.cgs6.local,Nginx Web Server,sv01-web.cgs6.local,DNS Server,sv01-web.cgs6.local,NGINX Load,sv01-web.cgs6.local,DNS Load
}

###############################################################################
# ServiceGroups for SV02 (sv02-owncloud.cgs6.local)
###############################################################################

define servicegroup{
    servicegroup_name       sv02-vm-resources
    alias                   SV02 VM Resources
    members                 sv02-owncloud.cgs6.local,CPU Utilization,sv02-owncloud.cgs6.local,Memory Utilization,sv02-owncloud.cgs6.local,Disk Usage,sv02-owncloud.cgs6.local,Swap Usage,sv02-owncloud.cgs6.local,Network Errors,sv02-owncloud.cgs6.local,POSIX Lock Monitor,sv02-owncloud.cgs6.local,FLOCK Lock Monitor
}

define servicegroup{
    servicegroup_name       sv02-app-services
    alias                   SV02 Application Services
    members                 sv02-owncloud.cgs6.local,OwnCloud HTTP,sv02-owncloud.cgs6.local,Samba/CIFS,sv02-owncloud.cgs6.local,MariaDB Connection,sv02-owncloud.cgs6.local,Owncloud HTTP Load,sv02-owncloud.cgs6.local,MySQL Load,sv02-owncloud.cgs6.local,Samba Load
}
EOF

log "Service groups configuration created"

# === CONFIGURAÇÃO PRINCIPAL DO NAGIOS ===

log "=== UPDATING MAIN NAGIOS CONFIGURATION ==="

# Backup da configuração principal
cp /usr/local/nagios/etc/nagios.cfg /usr/local/nagios/etc/nagios.cfg.backup

# Adiciona os novos arquivos de configuração
log "Adding configuration files to nagios.cfg..."
cat >> /usr/local/nagios/etc/nagios.cfg << 'EOF'

# FICHEIROS DE HOSTS ADICIONADO POR NOS
cfg_file=/usr/local/nagios/etc/objects/hosts.cfg
cfg_file=/usr/local/nagios/etc/objects/services.cfg
cfg_file=/usr/local/nagios/etc/objects/servicegroups.cfg
EOF

log "Main configuration updated"

# Validação final da configuração
log "Final validation of Nagios configuration..."
sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

if [ $? -eq 0 ]; then
  log "Final Nagios configuration is valid"
else
  log "ERROR: Final Nagios configuration validation failed"
  exit 1
fi

sudo systemctl restart nagios

# === FAIL2BAN ===

log "=== CONFIGURING FAIL2BAN ==="

apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban

# Configuração do Fail2Ban
log "Creating Fail2Ban configuration..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log

[apache-auth]
enabled  = true
port     = http,https
filter   = apache-auth
logpath  = /var/log/apache2/error.log
EOF

systemctl restart fail2ban

# Verifica status do Fail2Ban
log "Verifying Fail2Ban status..."
fail2ban-client status
fail2ban-client status sshd
fail2ban-client status apache-auth

log "Fail2Ban configured successfully"

# === VERIFICAÇÃO FINAL ===

log "=== FINAL VERIFICATION ==="

services=("apache2" "nagios" "fail2ban")
for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    log "✓ $service is running"
  else
    log "⚠️  $service is not running"
    systemctl status "$service" --no-pager -l
  fi
done

log "=== NAGIOS CORE SERVER CONFIGURATION COMPLETED ==="
log "🎉 INSTALLATION SUMMARY:"
log "Nagios Web Interface: http://[SERVER_IP]/nagios"
log "Username: nagiosadmin"
log "Password: [as configured during installation]"
log "Configuration files location: /usr/local/nagios/etc/"
log "Monitored servers:"
log "  - SV01 (Web/DNS): 10.101.150.66"
log "  - SV02 (OwnCloud): 10.101.150.67"
log "Check output_sv3.txt for detailed logs" 