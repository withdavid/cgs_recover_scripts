# Instala NGINX
sudo apt update -y
sudo apt installl nginx -y

# Configura portas expostas
ufw allow 22/tcp

ufw allow 80/tcp
ufw allow 443/tcp

ufw enable

# Instala DNS server

sudo apt install bind9 bind9utils bind9-doc dnsutils -y

# Permitir consulta DNS externa
ufw allow 53/tcp
ufw allow 53/udp

nano /etc/bind/named.conf.local
zone "cgs6.local" {
    type master;
    file "/etc/bind/db.cgs6.local";
};

sudo cp /etc/bind/db.local /etc/bind/db.cgs6.local
sudo nano /etc/bind/db.cgs6.local

;
; BIND data file for local loopback interface
;
$TTL    604800
@       IN      SOA     localhost. root.localhost. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      localhost.
@       IN      A       127.0.0.1
@       IN      AAAA    ::1

; Name servers
        IN      NS      ns.cgs6.local.

; A records
ns              IN      A       10.101.150.66
www             IN      A       10.101.150.66
owncloud        IN      A       10.101.150.67
share           IN      A       10.101.150.67

# Instala NRPE
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

#Alterar campos allowed_hosts para incluir IP do Servidor do Nagios:
allowed_hosts=127.0.0.1,::1,10.101.150.68


sudo ufw allow 5666/tcp

sudo mkdir -p /usr/local/nagios/var
sudo chown nagios:nagios /usr/local/nagios/var

sudo systemctl restart nrpe
sudo systemctl status nrpe
/usr/local/nagios/libexec/check_nrpe -H localhost

# INstala mais dependencias
sudo apt install nagios-plugins nagios-plugins-contrib


# monitorização de serviços

nano /usr/local/nagios/etc/nrpe.cfg

# Monitora o estado dos serviços
command[check_nginx]=/usr/local/nagios/libexec/check_http -I 10.101.150.66 -p 80
command[check_dns]=/usr/local/nagios/libexec/check_dns -H google.com -s 10.101.150.66

# Monitora o load dos serviços
command[check_http_cpu]=/usr/local/nagios/libexec/check_service_cpu.sh nginx 20% 50%
command[check_dns_cpu]=/usr/local/nagios/libexec/check_service_cpu.sh named 5% 20%


# Verifica por LOCKS em POSIX/FLOCK
command[check_posix_locks]=/usr/local/nagios/libexec/check_locks.sh --type=POSIX --warning=10 --critical=20
command[check_flock_locks]=/usr/local/nagios/libexec/check_locks.sh --type=FLOCK --warning=5 --critical=10

# Monitora os recursos da VM
# CPU utilization
command[check_cpu]=/usr/lib/nagios/plugins/check_cpu -w 80% -c 90%

# Memory utilization
command[check_mem]=/usr/lib/nagios/plugins/check_memory -w 80% -c 90%

# Root partition usage
command[check_disk_root]=/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /

# Swap usage
command[check_swap]=/usr/lib/nagios/plugins/check_swap -w 20% -c 10%

# Network errors on eth0
command[check_net_err]=/usr/lib/nagios/plugins/check_network_errors -i ens18 -w 100 -c 200


cria ficheiro /usr/local/nagios/libexec/check_service_cpu.sh

```
#!/bin/bash
#
# check_service_cpu.sh - soma %CPU de todos os processos de um serviço
# Uso: check_service_cpu.sh <proc_name> <warn_%> <crit_%>

if [ $# -ne 3 ]; then
  echo "Usage: $0 <process_name> <warn_%> <crit_%>"
  exit 3
fi

PROC_NAME=$1
WARN=${2%\%}    # aceita “80%” ou “80”
CRIT=${3%\%}

# Soma o %CPU de todos os processos com aquele nome
CPU_SUM=$(ps -C "$PROC_NAME" -o %cpu= | awk '{sum+=$1} END{print sum+0}')

# Perfdata
PERF="cpu=${CPU_SUM}%;${WARN};${CRIT};0;100"

if (( $(echo "$CPU_SUM >= $CRIT" | bc -l) )); then
  echo "CRITICAL - $PROC_NAME CPU load ${CPU_SUM}% |$PERF"
  exit 2
elif (( $(echo "$CPU_SUM >= $WARN" | bc -l) )); then
  echo "WARNING - $PROC_NAME CPU load ${CPU_SUM}% |$PERF"
  exit 1
else
  echo "OK - $PROC_NAME CPU load ${CPU_SUM}% |$PERF"
  exit 0
fi
```

chmod +x /usr/local/nagios/libexec/check_service_cpu.sh
chown nagios:nagios /usr/local/nagios/libexec/check_service_cpu.sh

systemctl restart nrpe


# Monitorização de locks POSIX - FLOCK

cria ficheiro /usr/local/nagios/libexec/check_locks.sh
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

systemctl restart nrpe

# Instalação de Fail2Ban

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

[nginx-http-auth]
enabled  = true
port    = http,https
filter  = nginx-http-auth
logpath = /var/log/nginx/error.log
```

systemctl restart fail2ban

fail2ban-client status
fail2ban-client status sshd
fail2ban-client status nginx-http-auth