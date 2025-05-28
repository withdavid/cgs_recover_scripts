#!/usr/bin/env bash

# ===============================
# Health Check Script for Server2 (OwnCloud + Samba)
# ===============================

echo "=== HEALTH CHECK SERVER2 ==="
echo "Timestamp: $(date)"
echo

# Test 1: Check if all services are running
echo "1. Checking service status..."
services=("apache2" "mariadb" "redis-server" "smbd" "nrpe" "fail2ban")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "$service is running"
    else
        echo "$service is NOT running"
    fi
done
echo

# Test 2: Check if configuration files exist
echo "2. Checking configuration files..."
config_files=(
    "/etc/apache2/sites-available/owncloud.conf"
    "/var/www/owncloud/config/config.php"
    "/etc/samba/smb.conf"
    "/etc/fail2ban/jail.local"
    "/etc/fail2ban/filter.d/owncloud-auth.conf"
    "/etc/fail2ban/filter.d/samba-auth.conf"
    "/usr/local/nagios/etc/nrpe.cfg"
)

for file in "${config_files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "$file exists ($(stat -c%s "$file") bytes)"
    else
        echo "$file is missing"
    fi
done
echo

# Test 3: Check if monitoring scripts exist
echo "3. Checking monitoring scripts..."
scripts=(
    "/usr/local/nagios/libexec/check_service_cpu.sh"
    "/usr/local/nagios/libexec/check_locks.sh"
    "/usr/local/nagios/libexec/check_smb_share"
    "/usr/lib/nagios/plugins/check_smb_share"
)

for script in "${scripts[@]}"; do
    if [[ -f "$script" && -x "$script" ]]; then
        echo "$script exists and is executable"
    else
        echo "$script is missing or not executable"
    fi
done
echo

# Test 4: Test NRPE connection
echo "4. Testing NRPE connection..."
if command -v /usr/local/nagios/libexec/check_nrpe &>/dev/null; then
    if /usr/local/nagios/libexec/check_nrpe -H localhost &>/dev/null; then
        echo "NRPE connection successful"
    else
        echo "NRPE connection failed"
    fi
else
    echo "check_nrpe command not found"
fi
echo

# Test 5: Test OwnCloud web interface
echo "5. Testing OwnCloud web interface..."
if curl -s http://localhost | grep -q "ownCloud"; then
    echo "OwnCloud web interface responding"
else
    echo "OwnCloud web interface not responding"
fi
echo

# Test 6: Test MariaDB connection
echo "6. Testing MariaDB connection..."
if mysql -u owncloud -p"OwncloudDB#password123" -e "USE owncloud; SHOW TABLES;" &>/dev/null; then
    echo "MariaDB connection successful"
else
    echo "MariaDB connection failed"
fi
echo

# Test 7: Test Samba share
echo "7. Testing Samba share..."
if smbclient -L localhost -N 2>/dev/null | grep -q "grupo6"; then
    echo "Samba share 'grupo6' is available"
else
    echo "Samba share 'grupo6' not found"
fi
echo

# Test 8: Check Fail2Ban jails
echo "8. Checking Fail2Ban jails..."
if command -v fail2ban-client &>/dev/null; then
    jail_count=$(fail2ban-client status 2>/dev/null | grep -c "Jail list:" || echo "0")
    if [[ $jail_count -gt 0 ]]; then
        echo "Fail2Ban jails active:"
        fail2ban-client status 2>/dev/null
    else
        echo "No Fail2Ban jails active"
    fi
else
    echo "fail2ban-client not found"
fi
echo

# Test 9: Check firewall rules
echo "9. Checking firewall rules..."
if ufw status | grep -q "Status: active"; then
    echo "UFW firewall is active"
    echo "Open ports:"
    ufw status | grep ALLOW
else
    echo "UFW firewall is not active"
fi
echo

# Test 10: Check OwnCloud version and status
echo "10. Checking OwnCloud status..."
if command -v occ &>/dev/null; then
    echo "OwnCloud version: $(occ -V 2>/dev/null || echo 'Unknown')"
    echo "OwnCloud status: $(occ status --output=json 2>/dev/null | jq -r '.installed' || echo 'Unknown')"
else
    echo "OCC command not found"
fi
echo

# Test 11: Check Redis connection
echo "11. Testing Redis connection..."
if redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "Redis is responding"
else
    echo "Redis is not responding"
fi
echo

# Test 12: Check disk space
echo "12. Checking disk space..."
df_output=$(df -h / | tail -1)
used_percent=$(echo "$df_output" | awk '{print $5}' | sed 's/%//')
if [[ $used_percent -lt 80 ]]; then
    echo "Disk usage: $used_percent% (OK)"
else
    echo "⚠ Disk usage: $used_percent% (Warning: >80%)"
fi
echo

# Test 13: Check system load
echo "13. Checking system load..."
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
echo "Current load average: $load_avg"
echo

echo "=== HEALTH CHECK COMPLETED ===" 