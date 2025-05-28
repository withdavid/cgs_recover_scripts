# Instalação owncloud + mariadb

# Define o domain name
my_domain="owncloud.cgs6.local"
echo $my_domain

hostnamectl set-hostname $my_domain
hostname -f

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

# Instala os packages necessários
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

# Instala o SMBClient PHP Module
apt-get install -y php7.4-smbclient
echo "extension=smbclient.so" > /etc/php/7.4/mods-available/smbclient.ini
phpenmod smbclient
systemctl restart apache2

# Verifica se foi ativado com sucesso
php -m | grep smbclient

# Instala pacotes recomendados pelo owncloud
apt install -y \
  unzip bzip2 rsync curl jq \
  inetutils-ping  ldap-utils\
  smbclient

# Configuração do Apache2
# Criação de Virtual Hosts

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
apachectl -t

# Insere o domain name na configuração do apache
echo "ServerName $my_domain" >> /etc/apache2/apache2.conf

# Habilita a configuração Virtual Host
a2dissite 000-default
a2ensite owncloud.conf

# Configuração de base de dados MariaDB
sed -i "/\[mysqld\]/atransaction-isolation = READ-COMMITTED\nperformance_schema = on" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl start mariadb

mysql -u root -e \
"CREATE DATABASE IF NOT EXISTS owncloud; \
CREATE USER IF NOT EXISTS 'owncloud'@'localhost' IDENTIFIED BY 'OwncloudDB#password123'; \
GRANT ALL PRIVILEGES ON owncloud.* TO 'owncloud'@'localhost' WITH GRANT OPTION; \
FLUSH PRIVILEGES;"

# Habilita modulos Apache recomendados e reinicia o serviço
a2enmod dir env headers mime rewrite setenvif
systemctl restart apache2

# Download Owncload
cd /var/www/
wget https://download.owncloud.com/server/stable/owncloud-complete-latest.tar.bz2 && \
tar -xjf owncloud-complete-latest.tar.bz2 && \
chown -R www-data. owncloud

# Instalação Owncload
occ maintenance:install \
--database "mysql" \
--database-name "owncloud" \
--database-user "owncloud" \
--database-pass "OwncloudDB#password123" \
--data-dir "/var/www/owncloud/data" \
--admin-user "admin" \
--admin-pass "OwnCloud#server2_password123"

# Configura os dominios confiáveis (Trusted Domains)
my_ip=$(hostname -I|cut -f1 -d ' ')
occ config:system:set trusted_domains 1 --value="$my_ip"
occ config:system:set trusted_domains 2 --value="$my_domain"

# Define o cron job para modo background
occ background:cron

# Define a execução do cronjon para a cada 15 minutos e elimina os chuncks todas as noites às 02:00H
echo "*/15  *  *  *  * /var/www/owncloud/occ system:cron" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
echo "0  2  *  *  * /var/www/owncloud/occ dav:cleanup-chunks" \
  | sudo -u www-data -g crontab tee -a \
  /var/spool/cron/crontabs/www-data
  
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

# Finaliza o processo de instalação
cd /var/www/
chown -R www-data. owncloud

occ -V
echo "Your ownCloud is accessable under: "$my_ip
echo "Your ownCloud is accessable under: "$my_domain
echo "The Installation is complete."

# UFW


# Permite acesso externo SSH
ufw allow 22/tcp

# Permite acesso externo HTTP & HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Habilita o ufw
ufw enable

# samba server


# Atualização de packages ubuntu
apt update && sudo apt upgrade -y

# Instalação do Samba
apt install samba -y

# Verifica versão instalad
samba --version

# Edição do ficheiro de configuração do samba
nano /etc/samba/smb.conf
```
[grupo6]
   comment = Pasta partilhada grupo 6
   path = /home/grupo6/pasta_grupo6
   valid users = grupo6
   browseable = yes
   writable = yes
   guest ok = no
   read only = no
```

sudo adduser grupo6
sudo smbpasswd -a grupo6
mkdir -p /home/grupo6/pasta_grupo6
sudo chown grupo6:grupo6 /home/grupo6/pasta_grupo6
systemctl restart smbd

ufw allow 445/tcp

# instalação NRPE

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

sudo nano /usr/local/nagios/etc/nrpe.cfg

```
#############################################################################
#
#  Sample NRPE Config File
#
#  Notes:
#
#  This is a sample configuration file for the NRPE daemon.  It needs to be
#  located on the remote host that is running the NRPE daemon, not the host
#  from which the check_nrpe client is being executed.
#
#############################################################################


# LOG FACILITY
# The syslog facility that should be used for logging purposes.

log_facility=daemon

# COMANDO ADICIONADO POR NOS

# Monitora o estado dos serviços
command[check_samba]=/usr/lib/nagios/plugins/check_smb_share -H 10.101.150.67 -s grupo6 -u grupo6 -p grupo6_samba123!
command[check_mariadb]=/usr/lib/nagios/plugins/check_mysql -H 127.0.0.1 -u owncloud -p "OwncloudDB#password123" -d owncloud

# Monitora o load dos serviços
command[check_http_cpu]=/usr/local/nagios/libexec/check_service_cpu.sh apache2 30% 70%
command[check_mysql_cpu]=/usr/local/nagios/libexec/check_service_cpu.sh mysqld 10% 30%
command[check_samba_cpu]=/usr/local/nagios/libexec/check_service_cpu.sh smbd 5% 20%

# Monitora os locks em POSIX / FLOCKS
command[check_posix_locks]=/usr/local/nagios/libexec/check_locks.sh --type=POSIX --warning=10 --critical=20
command[check_flock_locks]=/usr/local/nagios/libexec/check_locks.sh --type=FLOCK --warning=5 --critical=10

# Monitora os recursos da VM
# CPU utilization
command[check_cpu]=/usr/lib/nagios/plugins/check_cpu -w 80% -c 90%

# Memory utilization (usa o plugin check_memory que já tens instalado)
command[check_mem]=/usr/lib/nagios/plugins/check_memory -w 80% -c 90%

# Root partition usage
command[check_disk_root]=/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /

# Swap usage
command[check_swap]=/usr/lib/nagios/plugins/check_swap -w 20% -c 10%

# Network errors on eth0
command[check_net_err]=/usr/lib/nagios/plugins/check_network_errors -i ens18 -w 100 -c 200


# LOG FILE
# If a log file is specified in this option, nrpe will write to
# that file instead of using syslog.

#log_file=/usr/local/nagios/var/nrpe.log



# DEBUGGING OPTION
# This option determines whether or not debugging messages are logged to the
# syslog facility.
# Values: 0=debugging off, 1=debugging on

debug=0



# PID FILE
# The name of the file in which the NRPE daemon should write it's process ID
# number.  The file is only written if the NRPE daemon is started by the root
# user and is running in standalone mode.

pid_file=/usr/local/nagios/var/nrpe.pid



# PORT NUMBER
# Port number we should wait for connections on.
# NOTE: This must be a non-privileged port (i.e. > 1024).
# NOTE: This option is ignored if NRPE is running under either inetd or xinetd

server_port=5666



# SERVER ADDRESS
# Address that nrpe should bind to in case there are more than one interface
# and you do not want nrpe to bind on all interfaces.
# NOTE: This option is ignored if NRPE is running under either inetd or xinetd

#server_address=127.0.0.1



# LISTEN QUEUE SIZE
# Listen queue size (backlog) for serving incoming connections.
# You may want to increase this value under high load.

#listen_queue_size=5



# NRPE USER
# This determines the effective user that the NRPE daemon should run as.
# You can either supply a username or a UID.
#
# NOTE: This option is ignored if NRPE is running under either inetd or xinetd

nrpe_user=nagios



# NRPE GROUP
# This determines the effective group that the NRPE daemon should run as.
# You can either supply a group name or a GID.
#
# NOTE: This option is ignored if NRPE is running under either inetd or xinetd

nrpe_group=nagios



# ALLOWED HOST ADDRESSES
# This is an optional comma-delimited list of IP address or hostnames
# that are allowed to talk to the NRPE daemon. Network addresses with a bit mask
# (i.e. 192.168.1.0/24) are also supported. Hostname wildcards are not currently
# supported.
#
# Note: The daemon only does rudimentary checking of the client's IP
# address.  I would highly recommend adding entries in your /etc/hosts.allow
# file to allow only the specified host to connect to the port
# you are running this daemon on.
#
# NOTE: This option is ignored if NRPE is running under either inetd or xinetd

allowed_hosts=127.0.0.1,::1,10.101.150.68



# COMMAND ARGUMENT PROCESSING
# This option determines whether or not the NRPE daemon will allow clients
# to specify arguments to commands that are executed.  This option only works
# if the daemon was configured with the --enable-command-args configure script
# option.
#
# *** ENABLING THIS OPTION IS A SECURITY RISK! ***
# Read the SECURITY file for information on some of the security implications
# of enabling this variable.
#
# Values: 0=do not allow arguments, 1=allow command arguments

dont_blame_nrpe=0



# BASH COMMAND SUBSTITUTION
# This option determines whether or not the NRPE daemon will allow clients
# to specify arguments that contain bash command substitutions of the form
# $(...).  This option only works if the daemon was configured with both
# the --enable-command-args and --enable-bash-command-substitution configure
# script options.
#
# *** ENABLING THIS OPTION IS A HIGH SECURITY RISK! ***
# Read the SECURITY file for information on some of the security implications
# of enabling this variable.
#
# Values: 0=do not allow bash command substitutions,
#         1=allow bash command substitutions

allow_bash_command_substitution=0



# COMMAND PREFIX
# This option allows you to prefix all commands with a user-defined string.
# A space is automatically added between the specified prefix string and the
# command line from the command definition.
#
# *** THIS EXAMPLE MAY POSE A POTENTIAL SECURITY RISK, SO USE WITH CAUTION! ***
# Usage scenario:
# Execute restricted commmands using sudo.  For this to work, you need to add
# the nagios user to your /etc/sudoers.  An example entry for allowing
# execution of the plugins from might be:
#
# nagios          ALL=(ALL) NOPASSWD: /usr/lib/nagios/plugins/
#
# This lets the nagios user run all commands in that directory (and only them)
# without asking for a password.  If you do this, make sure you don't give
# random users write access to that directory or its contents!

# command_prefix=/usr/bin/sudo


# MAX COMMANDS
# This specifies how many children processes may be spawned at any one
# time, essentially limiting the fork()s that occur.
# Default (0) is set to unlimited
# max_commands=0



# COMMAND TIMEOUT
# This specifies the maximum number of seconds that the NRPE daemon will
# allow plugins to finish executing before killing them off.

command_timeout=60



# CONNECTION TIMEOUT
# This specifies the maximum number of seconds that the NRPE daemon will
# wait for a connection to be established before exiting. This is sometimes
# seen where a network problem stops the SSL being established even though
# all network sessions are connected. This causes the nrpe daemons to
# accumulate, eating system resources. Do not set this too low.

connection_timeout=300



# WEAK RANDOM SEED OPTION
# This directive allows you to use SSL even if your system does not have
# a /dev/random or /dev/urandom (on purpose or because the necessary patches
# were not applied). The random number generator will be seeded from a file
# which is either a file pointed to by the environment valiable $RANDFILE
# or $HOME/.rnd. If neither exists, the pseudo random number generator will
# be initialized and a warning will be issued.
# Values: 0=only seed from /dev/[u]random, 1=also seed from weak randomness

#allow_weak_random_seed=1



# SSL/TLS OPTIONS
# These directives allow you to specify how to use SSL/TLS.

# SSL VERSION
# This can be any of: SSLv2 (only use SSLv2), SSLv2+ (use any version),
#        SSLv3 (only use SSLv3), SSLv3+ (use SSLv3 or above), TLSv1 (only use
#        TLSv1), TLSv1+ (use TLSv1 or above), TLSv1.1 (only use TLSv1.1),
#        TLSv1.1+ (use TLSv1.1 or above), TLSv1.2 (only use TLSv1.2),
#        TLSv1.2+ (use TLSv1.2 or above)
# If an "or above" version is used, the best will be negotiated. So if both
# ends are able to do TLSv1.2 and use specify SSLv2, you will get TLSv1.2.
# If you are using openssl 1.1.0 or above, the SSLv2 options are not available.

#ssl_version=SSLv2+

# SSL USE ADH
# This is for backward compatibility and is DEPRECATED. Set to 1 to enable
# ADH or 2 to require ADH. 1 is currently the default but will be changed
# in a later version.

#ssl_use_adh=1

# SSL CIPHER LIST
# This lists which ciphers can be used. For backward compatibility, this
# defaults to 'ssl_cipher_list=ALL:!MD5:@STRENGTH' for < OpenSSL 1.1.0,
# and 'ssl_cipher_list=ALL:!MD5:@STRENGTH:@SECLEVEL=0' for OpenSSL 1.1.0 and
# greater. 

#ssl_cipher_list=ALL:!MD5:@STRENGTH
#ssl_cipher_list=ALL:!MD5:@STRENGTH:@SECLEVEL=0
#ssl_cipher_list=ALL:!aNULL:!eNULL:!SSLv2:!LOW:!EXP:!RC4:!MD5:@STRENGTH

# SSL Certificate and Private Key Files

#ssl_cacert_file=/etc/ssl/servercerts/ca-cert.pem
#ssl_cert_file=/etc/ssl/servercerts/nagios-cert.pem
#ssl_privatekey_file=/etc/ssl/servercerts/nagios-key.pem

# SSL USE CLIENT CERTS
# This options determines client certificate usage.
# Values: 0 = Don't ask for or require client certificates (default)
#         1 = Ask for client certificates
#         2 = Require client certificates

#ssl_client_certs=0

# SSL LOGGING
# This option determines which SSL messages are send to syslog. OR values
# together to specify multiple options.

# Values: 0x00 (0)  = No additional logging (default)
#         0x01 (1)  = Log startup SSL/TLS parameters
#         0x02 (2)  = Log remote IP address
#         0x04 (4)  = Log SSL/TLS version of connections
#         0x08 (8)  = Log which cipher is being used for the connection
#         0x10 (16) = Log if client has a certificate
#         0x20 (32) = Log details of client's certificate if it has one
#         -1 or 0xff or 0x2f = All of the above

#ssl_logging=0x00



# NASTY METACHARACTERS
# This option allows you to override the list of characters that cannot
# be passed to the NRPE daemon.

# nasty_metachars=|`&><'\\[]{};\r\n

# This option allows you to enable or disable logging error messages to the syslog facilities.
# If this option is not set, the error messages will be logged.
disable_syslog=0

# COMMAND DEFINITIONS
# Command definitions that this daemon will run.  Definitions
# are in the following format:
#
# command[<command_name>]=<command_line>
#
# When the daemon receives a request to return the results of <command_name>
# it will execute the command specified by the <command_line> argument.
#
# Unlike Nagios, the command line cannot contain macros - it must be
# typed exactly as it should be executed.
#
# Note: Any plugins that are used in the command lines must reside
# on the machine that this daemon is running on!  The examples below
# assume that you have plugins installed in a /usr/local/nagios/libexec
# directory.  Also note that you will have to modify the definitions below
# to match the argument format the plugins expect.  Remember, these are
# examples only!


# The following examples use hardcoded command arguments...
# This is by far the most secure method of using NRPE

command[check_users]=/usr/local/nagios/libexec/check_users -w 5 -c 10
command[check_load]=/usr/local/nagios/libexec/check_load -r -w .15,.10,.05 -c .30,.25,.20
command[check_hda1]=/usr/local/nagios/libexec/check_disk -w 20% -c 10% -p /dev/hda1
command[check_zombie_procs]=/usr/local/nagios/libexec/check_procs -w 5 -c 10 -s Z
command[check_total_procs]=/usr/local/nagios/libexec/check_procs -w 150 -c 200


# The following examples allow user-supplied arguments and can
# only be used if the NRPE daemon was compiled with support for
# command arguments *AND* the dont_blame_nrpe directive in this
# config file is set to '1'.  This poses a potential security risk, so
# make sure you read the SECURITY file before doing this.

### MISC SYSTEM METRICS ###
#command[check_users]=/usr/local/nagios/libexec/check_users $ARG1$
#command[check_load]=/usr/local/nagios/libexec/check_load $ARG1$
#command[check_disk]=/usr/local/nagios/libexec/check_disk $ARG1$
#command[check_swap]=/usr/local/nagios/libexec/check_swap $ARG1$
#command[check_cpu_stats]=/usr/local/nagios/libexec/check_cpu_stats.sh $ARG1$
#command[check_mem]=/usr/local/nagios/libexec/custom_check_mem -n $ARG1$

### GENERIC SERVICES ###
#command[check_init_service]=sudo /usr/local/nagios/libexec/check_init_service $ARG1$
#command[check_services]=/usr/local/nagios/libexec/check_services -p $ARG1$

### SYSTEM UPDATES ###
#command[check_yum]=/usr/local/nagios/libexec/check_yum
#command[check_apt]=/usr/local/nagios/libexec/check_apt

### PROCESSES ###
#command[check_all_procs]=/usr/local/nagios/libexec/custom_check_procs
#command[check_procs]=/usr/local/nagios/libexec/check_procs $ARG1$

### OPEN FILES ###
#command[check_open_files]=/usr/local/nagios/libexec/check_open_files.pl $ARG1$

### NETWORK CONNECTIONS ###
#command[check_netstat]=/usr/local/nagios/libexec/check_netstat.pl -p $ARG1$ $ARG2$

### ASTERISK ###
#command[check_asterisk]=/usr/local/nagios/libexec/check_asterisk.pl $ARG1$
#command[check_sip]=/usr/local/nagios/libexec/check_sip $ARG1$
#command[check_asterisk_sip_peers]=sudo /usr/local/nagios/libexec/check_asterisk_sip_peers.sh $ARG1$
#command[check_asterisk_version]=/usr/local/nagios/libexec/nagisk.pl -c version
#command[check_asterisk_peers]=/usr/local/nagios/libexec/nagisk.pl -c peers
#command[check_asterisk_channels]=/usr/local/nagios/libexec/nagisk.pl -c channels 
#command[check_asterisk_zaptel]=/usr/local/nagios/libexec/nagisk.pl -c zaptel 
#command[check_asterisk_span]=/usr/local/nagios/libexec/nagisk.pl -c span -s 1



# INCLUDE CONFIG FILE
# This directive allows you to include definitions from an external config file.

#include=<somefile.cfg>



# INCLUDE CONFIG DIRECTORY
# This directive allows you to include definitions from config files (with a
# .cfg extension) in one or more directories (with recursion).

#include_dir=<somedirectory>
#include_dir=<someotherdirectory>

# KEEP ENVIRONMENT VARIABLES
# This directive allows you to retain specific variables from the environment
# when starting the NRPE daemon. 

#keep_env_vars=NRPE_MULTILINESUPPORT,NRPE_PROGRAMVERSION
```

sudo ufw allow 5666/tcp

sudo mkdir -p /usr/local/nagios/var
sudo chown nagios:nagios /usr/local/nagios/var

sudo systemctl restart nrpe
sudo systemctl status nrpe
/usr/local/nagios/libexec/check_nrpe -H localhost

# instala dependencias agentes

sudo apt install nagios-plugins nagios-plugins-contrib


nano /usr/lib/nagios/plugins/check_smb_share

```
#!/bin/sh

# Check for sharename on SMB with nagios
# Michael Hodges <michael@va.com.au> 2011-03-04
# Modified version of check_smb by Dave Love <fx@gnu.org>

REVISION=1.0
PROGNAME=`/usr/bin/basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`

. $PROGPATH/utils.sh

usage () {
    echo "\
Nagios plugin to check for SAMBA Share. Use anonymous login if username is not supplied. 

Usage:
  $PROGNAME -H <host> -s <"sharename">
  $PROGNAME -H <host> -s <"sharename"> -u <username> -p <password>
  $PROGNAME --help
  $PROGNAME --version
"
}

help () {
    print_revision $PROGNAME $REVISION
    echo; usage; echo; support
}

if [ $# -lt 1 ]; then
    usage
    exit $STATE_UNKNOWN
fi

username="guest"
password=""

while test -n "$1"; do
    case "$1" in
        --help | -h)
            help
            exit $STATE_OK;;
        --version | -V)
            print_revision $PROGNAME $REVISION
            exit $STATE_OK;;
        -H)
            shift
            host="$1";;
        -s)
            shift
            share="$1";;
        -u)
            shift
            username="$1";;
        -p)
            shift
            password="$1";;
        *)
            usage; exit $STATE_UNKNOWN;;
    esac
shift
done

if [ "$username" = "guest" ]; then
        stdout=`smbclient -N -L "$host" 2>&1`
        sharetest=`echo "$stdout" | grep -o "$share" |head -n 1`
else
        stdout=`smbclient -L "$host" -U"$username"%"$password" 2>&1`
        sharetest=`echo "$stdout" | grep -o "$share" |head -n 1`
fi

if [ "$sharetest" = "$share" ]; then
        echo "OK SMB Sharename: `echo "$stdout" | grep "$share" |head -n 1`"
        exit $STATE_OK
else
        err=`echo "$stdout" | head -n 1`
        echo "CRITICAL SMB Sharename: "$share" "$err""
        exit $STATE_CRITICAL
fi
```

chmod +x check_smb_share
sudo systemctl restart nrpe


nano /usr/local/nagios/libexec/check_locks.sh
```
#!/bin/bash
#
# Nagios plugin to monitor the number of locks on the system
#

# Nagios return codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# Display usage information
usage() {
    echo "Usage: $0 --type=<POSIX|FLOCK> --warning=<warning_threshold> --critical=<critical_threshold>"
    echo
    echo "Options:"
    echo "  --type      Type of lock to monitor (POSIX or FLOCK)"
    echo "  --warning   Warning threshold for number of locks"
    echo "  --critical  Critical threshold for number of locks"
    exit $UNKNOWN
}

# Parse command line options
for i in "$@"; do
    case $i in
        --type=*)
            LOCK_TYPE="${i#*=}"
            ;;
        --warning=*)
            WARNING_THRESHOLD="${i#*=}"
            ;;
        --critical=*)
            CRITICAL_THRESHOLD="${i#*=}"
            ;;
        *)
            usage
            ;;
    esac
done

# Check if all required parameters are provided
if [ -z "$LOCK_TYPE" ] || [ -z "$WARNING_THRESHOLD" ] || [ -z "$CRITICAL_THRESHOLD" ]; then
    echo "UNKNOWN: Missing required parameters"
    usage
fi

# Validate lock type
if [ "$LOCK_TYPE" != "POSIX" ] && [ "$LOCK_TYPE" != "FLOCK" ]; then
    echo "UNKNOWN: Invalid lock type. Must be POSIX or FLOCK"
    exit $UNKNOWN
fi

# Validate thresholds
if ! [[ "$WARNING_THRESHOLD" =~ ^[0-9]+$ ]] || ! [[ "$CRITICAL_THRESHOLD" =~ ^[0-9]+$ ]]; then
    echo "UNKNOWN: Thresholds must be positive integers"
    exit $UNKNOWN
fi

# Check if /proc/locks exists
if [ ! -f "/proc/locks" ]; then
    echo "UNKNOWN: /proc/locks file not found"
    exit $UNKNOWN
fi

# Count locks of specified type
LOCK_COUNT=$(grep -c " $LOCK_TYPE " /proc/locks)

# Handle count error
if [ $? -ne 0 ]; then
    echo "UNKNOWN: Error reading /proc/locks"
    exit $UNKNOWN
fi

# Check thresholds and return appropriate status
if [ "$LOCK_COUNT" -ge "$CRITICAL_THRESHOLD" ]; then
    echo "CRITICAL: The system has $LOCK_COUNT $LOCK_TYPE locks, exceeding the critical threshold ($CRITICAL_THRESHOLD)"
    exit $CRITICAL
elif [ "$LOCK_COUNT" -ge "$WARNING_THRESHOLD" ]; then
    echo "WARNING: The system has $LOCK_COUNT $LOCK_TYPE locks, exceeding the warning threshold ($WARNING_THRESHOLD)"
    exit $WARNING
else
    echo "OK: The system has $LOCK_COUNT $LOCK_TYPE locks, which is within the normal range"
    exit $OK
fi 
```

chmod +x /usr/local/nagios/libexec/check_locks.sh
chown nagios:nagios /usr/local/nagios/libexec/check_locks.sh

#fail2ban

apt install fail2ban
systemctl enable fail2ban
systemctl start fail2ban

nano /etc/fail2ban/filter.d/owncloud-auth.conf
```
[Definition]
failregex = Login failed: .* Remote IP: <HOST>
```

nano /etc/fail2ban/filter.d/samba-auth.conf
```
[Definition]
failregex = .*smbd.*authentication failure.*rhost=<HOST>.*$
```

nano /etc/fail2ban/jail.local
```
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log

[owncloud-auth]
enabled  = true
port     = http,https
filter   = owncloud-auth
logpath  = /var/www/owncloud/data/owncloud.log
maxretry = 5

[samba-auth]
enabled  = true
port     = 445
filter   = samba-auth
logpath  = /var/log/samba/log.smbd
```

systemctl restart fail2ban

fail2ban-client status
fail2ban-client status sshd
fail2ban-client status owncloud-auth
fail2ban-client status samba-auth