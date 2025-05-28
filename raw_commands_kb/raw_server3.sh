# Instala o Nagios Core
sudo apt-get update
sudo apt-get install -y autoconf gcc libc6 make wget unzip apache2 php libapache2-mod-php libgd-dev ufw
sudo apt-get install -y openssl libssl-dev

cd /tmp
wget -O nagioscore.tar.gz $(wget -q -O - https://api.github.com/repos/NagiosEnterprises/nagioscore/releases/latest  | grep '"browser_download_url":' | grep -o 'https://[^"]*')
tar xzf nagioscore.tar.gz

cd /tmp/nagios-*
sudo ./configure --with-httpd-conf=/etc/apache2/sites-enabled
sudo make all

sudo make install-groups-users
sudo usermod -a -G nagios www-data

sudo make install

sudo make install-daemoninit

sudo make install-commandmode

sudo make install-config

sudo make install-webconf
sudo a2enmod rewrite
sudo a2enmod cgi

sudo ufw allow Apache
sudo ufw reload

sudo htpasswd -c /usr/local/nagios/etc/htpasswd.users nagiosadmin

sudo systemctl restart apache2.service

sudo systemctl start nagios.service

# instalação plugins essenciais nagios

sudo apt-get install -y autoconf gcc libc6 libmcrypt-dev make libssl-dev wget bc gawk dc build-essential snmp libnet-snmp-perl gettext

cd /tmp
wget -O nagios-plugins.tar.gz $(wget -q -O - https://api.github.com/repos/nagios-plugins/nagios-plugins/releases/latest  | grep '"browser_download_url":' | grep -o 'https://[^"]*')
tar zxf nagios-plugins.tar.gz

cd /tmp/nagios-plugins-*/
sudo ./configure
sudo make
sudo make install

sudo systemctl start nagios.service
sudo systemctl stop nagios.service
sudo systemctl restart nagios.service
sudo systemctl status nagios.service

nano /usr/local/nagios/etc/objects/hosts.cfg
```
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
```

nano /usr/local/nagios/etc/objects/commands.cfg
```
###############################################################################
# COMMANDS.CFG - SAMPLE COMMAND DEFINITIONS FOR NAGIOS 4.5.9
#
#
# NOTES: This config file provides you with some example command definitions
#        that you can reference in host, service, and contact definitions.
#
#        You don't need to keep commands in a separate file from your other
#        object definitions.  This has been done just to make things easier to
#        understand.
#
###############################################################################


# COMANDOS ALTERADO POR NOS

define command{
    command_name    check_nrpe
    command_line    /usr/lib/nagios/plugins/check_nrpe -H $HOSTADDRESS$ -c $ARG1$
}

################################################################################
#
# SAMPLE NOTIFICATION COMMANDS
#
# These are some example notification commands.  They may or may not work on
# your system without modification.  As an example, some systems will require
# you to use "/usr/bin/mailx" instead of "/usr/bin/mail" in the commands below.
#
################################################################################

define command {

    command_name    notify-host-by-email
    command_line    /usr/bin/printf "%b" "***** Nagios *****\n\nNotification Type: $NOTIFICATIONTYPE$\nHost: $HOSTNAME$\nState: $HOSTSTATE$\nAddress: $HOSTADDRESS$\nInfo: $HOSTOUTPUT$\n\nDate/Time: $LONGDATETIME$\n" | /bin/mail -s "** $NOTIFICATIONTYPE$ Host Alert: $HOSTNAME$ is $HOSTSTATE$ **" $CONTACTEMAIL$
}



define command {

    command_name    notify-service-by-email
    command_line    /usr/bin/printf "%b" "***** Nagios *****\n\nNotification Type: $NOTIFICATIONTYPE$\n\nService: $SERVICEDESC$\nHost: $HOSTALIAS$\nAddress: $HOSTADDRESS$\nState: $SERVICESTATE$\n\nDate/Time: $LONGDATETIME$\n\nAdditional Info:\n\n$SERVICEOUTPUT$\n" | /bin/mail -s "** $NOTIFICATIONTYPE$ Service Alert: $HOSTALIAS$/$SERVICEDESC$ is $SERVICESTATE$ **" $CONTACTEMAIL$
}



################################################################################
#
# SAMPLE HOST CHECK COMMANDS
#
################################################################################

# This command checks to see if a host is "alive" by pinging it
# The check must result in a 100% packet loss or 5 second (5000ms) round trip
# average time to produce a critical error.
# Note: Five ICMP echo packets are sent (determined by the '-p 5' argument)

define command {

    command_name    check-host-alive
    command_line    $USER1$/check_ping -H $HOSTADDRESS$ -w 3000.0,80% -c 5000.0,100% -p 5
}



################################################################################
#
# SAMPLE SERVICE CHECK COMMANDS
#
# These are some example service check commands.  They may or may not work on
# your system, as they must be modified for your plugins.  See the HTML
# documentation on the plugins for examples of how to configure command definitions.
#
# NOTE:  The following 'check_local_...' functions are designed to monitor
#        various metrics on the host that Nagios is running on (i.e. this one).
################################################################################

define command {

    command_name    check_local_disk
    command_line    $USER1$/check_disk -w $ARG1$ -c $ARG2$ -p $ARG3$
}



define command {

    command_name    check_local_load
    command_line    $USER1$/check_load -w $ARG1$ -c $ARG2$
}



define command {

    command_name    check_local_procs
    command_line    $USER1$/check_procs -w $ARG1$ -c $ARG2$ -s $ARG3$
}



define command {

    command_name    check_local_users
    command_line    $USER1$/check_users -w $ARG1$ -c $ARG2$
}



define command {

    command_name    check_local_swap
    command_line    $USER1$/check_swap -w $ARG1$ -c $ARG2$
}



define command {

    command_name    check_local_mrtgtraf
    command_line    $USER1$/check_mrtgtraf -F $ARG1$ -a $ARG2$ -w $ARG3$ -c $ARG4$ -e $ARG5$
}



################################################################################
# NOTE:  The following 'check_...' commands are used to monitor services on
#        both local and remote hosts.
################################################################################

define command {

    command_name    check_ftp
    command_line    $USER1$/check_ftp -H $HOSTADDRESS$ $ARG1$
}



define command {

    command_name    check_hpjd
    command_line    $USER1$/check_hpjd -H $HOSTADDRESS$ $ARG1$
}



define command {

    command_name    check_snmp
    command_line    $USER1$/check_snmp -H $HOSTADDRESS$ $ARG1$
}



define command {

    command_name    check_http
    command_line    $USER1$/check_http -I $HOSTADDRESS$ $ARG1$
}



define command {

    command_name    check_ssh
    command_line    $USER1$/check_ssh $ARG1$ $HOSTADDRESS$
}



define command {

    command_name    check_dhcp
    command_line    $USER1$/check_dhcp $ARG1$
}



define command {

    command_name    check_ping
    command_line    $USER1$/check_ping -H $HOSTADDRESS$ -w $ARG1$ -c $ARG2$ -p 5
}



define command {

    command_name    check_pop
    command_line    $USER1$/check_pop -H $HOSTADDRESS$ $ARG1$
}



define command {

    command_name    check_imap
    command_line    $USER1$/check_imap -H $HOSTADDRESS$ $ARG1$
}



define command {

    command_name    check_smtp
    command_line    $USER1$/check_smtp -H $HOSTADDRESS$ $ARG1$
}



define command {

    command_name    check_tcp
    command_line    $USER1$/check_tcp -H $HOSTADDRESS$ -p $ARG1$ $ARG2$
}



define command {

    command_name    check_udp
    command_line    $USER1$/check_udp -H $HOSTADDRESS$ -p $ARG1$ $ARG2$
}



define command {

    command_name    check_nt
    command_line    $USER1$/check_nt -H $HOSTADDRESS$ -p 12489 -v $ARG1$ $ARG2$
}



################################################################################
#
# SAMPLE PERFORMANCE DATA COMMANDS
#
# These are sample performance data commands that can be used to send performance
# data output to two text files (one for hosts, another for services).  If you
# plan on simply writing performance data out to a file, consider using the
# host_perfdata_file and service_perfdata_file options in the main config file.
#
################################################################################

define command {

    command_name    process-host-perfdata
    command_line    /usr/bin/printf "%b" "$LASTHOSTCHECK$\t$HOSTNAME$\t$HOSTSTATE$\t$HOSTATTEMPT$\t$HOSTSTATETYPE$\t$HOSTEXECUTIONTIME$\t$HOSTOUTPUT$\t$HOSTPERFDATA$\n" >> /usr/local/nagios/var/host-perfdata.out
}



define command {

    command_name    process-service-perfdata
    command_line    /usr/bin/printf "%b" "$LASTSERVICECHECK$\t$HOSTNAME$\t$SERVICEDESC$\t$SERVICESTATE$\t$SERVICEATTEMPT$\t$SERVICESTATETYPE$\t$SERVICEEXECUTIONTIME$\t$SERVICELATENCY$\t$SERVICEOUTPUT$\t$SERVICEPERFDATA$\n" >> /usr/local/nagios/var/service-perfdata.out
}
```

nano /usr/local/nagios/etc/objects/services.cfg
```
### Serviços de Servidor 1 (sv01-web.cgs6.local)


## VM ResourceS

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
```

sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

sudo systemctl restart nagios

sudo nano /usr/local/nagios/etc/objects/contacts.cfg
```
###############################################################################
# CONTACTS.CFG - SAMPLE CONTACT/CONTACTGROUP DEFINITIONS
#
#
# NOTES: This config file provides you with some example contact and contact
#        group definitions that you can reference in host and service
#        definitions.
#
#        You don't need to keep these definitions in a separate file from your
#        other object definitions.  This has been done just to make things
#        easier to understand.
#
###############################################################################



###############################################################################
#
# CONTACTS
#
###############################################################################

# Just one contact defined by default - the Nagios admin (that's you)
# This contact definition inherits a lot of default values from the
# 'generic-contact' template which is defined elsewhere.

define contact {

    contact_name            nagiosadmin             ; Short name of user
    use                     generic-contact         ; Inherit default values from generic-contact template (defined above)
    alias                   Nagios Admin            ; Full name of user
    email                   jdoe@localhost.localdomain ; <<***** CHANGE THIS TO YOUR EMAIL ADDRESS ******
    #host_notifications_enabled      1
    #service_notifications_enabled   1
    #service_notification_commands   notify-by-email
    #host_notification_commands      host-notify-by-email
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
#
# CONTACT GROUPS
#
###############################################################################

# We only have one contact in this simple configuration file, so there is
# no need to create more than one contact group.

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
```

nano /usr/local/nagios/etc/objects/servicegroups.cfg
```
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
```

nano /usr/local/nagios/etc/nagios.cfg
```
# FICHEIROS DE HOSTS ADICIONADO POR NOS
cfg_file=/usr/local/nagios/etc/objects/hosts.cfg
cfg_file=/usr/local/nagios/etc/objects/services.cfg
cfg_file=/usr/local/nagios/etc/objects/servicegroups.cfg
```

sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg

sudo systemctl restart nagios

# fail2ban

apt install fail2ban
systemctl enable fail2ban
systemctl start fail2ban

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

[apache-auth]
enabled  = true
port     = http,https
filter   = apache-auth
logpath  = /var/log/apache2/error.log
```

systemctl restart fail2ban

fail2ban-client status
fail2ban-client status sshd
fail2ban-client status apache-auth