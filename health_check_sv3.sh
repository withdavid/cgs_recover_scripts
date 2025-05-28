#!/usr/bin/env bash

# ===============================
# Health Check Script for Server 3 (Nagios Core)
# Verifies all critical components of the monitoring server
# ===============================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log com timestamp e cores
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a health_check_sv3.txt
}

log_success() {
  log "${GREEN}✓ $*${NC}"
}

log_warning() {
  log "${YELLOW}⚠ $*${NC}"
}

log_error() {
  log "${RED}✗ $*${NC}"
}

log_info() {
  log "${BLUE}ℹ $*${NC}"
}

# Redirecionar toda a saída para health_check_sv3.txt e também para o terminal
exec > >(tee -a health_check_sv3.txt)
exec 2>&1

log_info "=== HEALTH CHECK SERVIDOR 3 (NAGIOS CORE) ==="
log_info "Timestamp: $(date)"
log_info "Hostname: $(hostname)"
log_info "IP Address: $(hostname -I | cut -d' ' -f1)"

# Contadores
total_checks=0
passed_checks=0
failed_checks=0
warning_checks=0

check_result() {
  total_checks=$((total_checks + 1))
  if [ $1 -eq 0 ]; then
    passed_checks=$((passed_checks + 1))
    log_success "$2"
  elif [ $1 -eq 2 ]; then
    warning_checks=$((warning_checks + 1))
    log_warning "$2"
  else
    failed_checks=$((failed_checks + 1))
    log_error "$2"
  fi
}

# === VERIFICAÇÃO DO SISTEMA ===

log_info "=== SYSTEM CHECKS ==="

# Verificar se é executado como root
if [[ $(id -u) -eq 0 ]]; then
  check_result 0 "Running as root user"
else
  check_result 1 "NOT running as root (some checks may fail)"
fi

# Verificar uptime
uptime_seconds=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)
uptime_hours=$((uptime_seconds / 3600))
if [ $uptime_hours -gt 0 ]; then
  check_result 0 "System uptime: ${uptime_hours} hours"
else
  check_result 2 "System uptime: ${uptime_seconds} seconds (recently rebooted)"
fi

# Verificar carga do sistema
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
load_threshold=2.0
if (( $(echo "$load_avg < $load_threshold" | bc -l) )); then
  check_result 0 "System load average: $load_avg (normal)"
else
  check_result 2 "System load average: $load_avg (high)"
fi

# Verificar uso de memória
mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
if (( $(echo "$mem_usage < 80" | bc -l) )); then
  check_result 0 "Memory usage: ${mem_usage}% (normal)"
elif (( $(echo "$mem_usage < 90" | bc -l) )); then
  check_result 2 "Memory usage: ${mem_usage}% (warning)"
else
  check_result 1 "Memory usage: ${mem_usage}% (critical)"
fi

# Verificar uso de disco
disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $disk_usage -lt 80 ]; then
  check_result 0 "Disk usage: ${disk_usage}% (normal)"
elif [ $disk_usage -lt 90 ]; then
  check_result 2 "Disk usage: ${disk_usage}% (warning)"
else
  check_result 1 "Disk usage: ${disk_usage}% (critical)"
fi

# === VERIFICAÇÃO DOS SERVIÇOS ===

log_info "=== SERVICE CHECKS ==="

# Lista de serviços críticos
services=("apache2" "nagios" "fail2ban")

for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    if systemctl is-enabled --quiet "$service"; then
      check_result 0 "$service is running and enabled"
    else
      check_result 2 "$service is running but not enabled"
    fi
  else
    check_result 1 "$service is not running"
    log_info "Service status: $(systemctl status $service --no-pager -l | head -3)"
  fi
done

# === VERIFICAÇÃO DO NAGIOS CORE ===

log_info "=== NAGIOS CORE CHECKS ==="

# Verificar se o Nagios está instalado
if [ -f "/usr/local/nagios/bin/nagios" ]; then
  check_result 0 "Nagios Core binary found"
  
  # Verificar versão do Nagios
  nagios_version=$(/usr/local/nagios/bin/nagios --version | head -1)
  log_info "Nagios version: $nagios_version"
else
  check_result 1 "Nagios Core binary not found"
fi

# Verificar configuração do Nagios
if [ -f "/usr/local/nagios/etc/nagios.cfg" ]; then
  check_result 0 "Nagios main configuration file found"
  
  # Validar configuração
  if /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg > /dev/null 2>&1; then
    check_result 0 "Nagios configuration is valid"
  else
    check_result 1 "Nagios configuration has errors"
    log_info "Configuration errors:"
    /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg 2>&1 | tail -10
  fi
else
  check_result 1 "Nagios main configuration file not found"
fi

# Verificar arquivos de configuração personalizados
config_files=(
  "/usr/local/nagios/etc/objects/hosts.cfg"
  "/usr/local/nagios/etc/objects/services.cfg"
  "/usr/local/nagios/etc/objects/contacts.cfg"
  "/usr/local/nagios/etc/objects/servicegroups.cfg"
)

for config_file in "${config_files[@]}"; do
  if [ -f "$config_file" ]; then
    check_result 0 "Configuration file found: $(basename $config_file)"
  else
    check_result 1 "Configuration file missing: $(basename $config_file)"
  fi
done

# Verificar usuário web do Nagios
if [ -f "/usr/local/nagios/etc/htpasswd.users" ]; then
  check_result 0 "Nagios web authentication file found"
  user_count=$(wc -l < /usr/local/nagios/etc/htpasswd.users)
  log_info "Web users configured: $user_count"
else
  check_result 1 "Nagios web authentication file not found"
fi

# === VERIFICAÇÃO DOS PLUGINS ===

log_info "=== NAGIOS PLUGINS CHECKS ==="

# Verificar diretório de plugins
if [ -d "/usr/local/nagios/libexec" ]; then
  check_result 0 "Nagios plugins directory found"
  
  plugin_count=$(ls -1 /usr/local/nagios/libexec/ | wc -l)
  log_info "Plugins installed: $plugin_count"
else
  check_result 1 "Nagios plugins directory not found"
fi

# Verificar plugins essenciais
essential_plugins=(
  "/usr/local/nagios/libexec/check_ping"
  "/usr/local/nagios/libexec/check_http"
  "/usr/local/nagios/libexec/check_ssh"
  "/usr/local/nagios/libexec/check_disk"
  "/usr/local/nagios/libexec/check_load"
  "/usr/lib/nagios/plugins/check_nrpe"
)

for plugin in "${essential_plugins[@]}"; do
  if [ -f "$plugin" ] && [ -x "$plugin" ]; then
    check_result 0 "Plugin found and executable: $(basename $plugin)"
    
    # Verificação especial para check_nrpe
    if [[ "$plugin" == *"check_nrpe"* ]]; then
      if $plugin --version > /dev/null 2>&1; then
        nrpe_version=$($plugin --version 2>&1 | head -1)
        log_info "NRPE client version: $nrpe_version"
      else
        check_result 2 "check_nrpe plugin has version issues"
      fi
    fi
  else
    check_result 1 "Plugin missing or not executable: $(basename $plugin)"
    
    # Para check_nrpe, tentar encontrar em localizações alternativas
    if [[ "$plugin" == *"check_nrpe"* ]]; then
      alternative_locations=(
        "/usr/local/nagios/libexec/check_nrpe"
        "/usr/lib/nagios/plugins/check_nrpe"
        "/usr/lib/monitoring-plugins/check_nrpe"
      )
      
      for alt_location in "${alternative_locations[@]}"; do
        if [ -f "$alt_location" ] && [ -x "$alt_location" ]; then
          check_result 2 "check_nrpe found at alternative location: $alt_location"
          break
        fi
      done
    fi
  fi
done

# === VERIFICAÇÃO DO APACHE ===

log_info "=== APACHE CHECKS ==="

# Verificar configuração do Apache
if [ -f "/etc/apache2/sites-enabled/nagios.conf" ]; then
  check_result 0 "Nagios Apache configuration found"
else
  check_result 1 "Nagios Apache configuration not found"
fi

# Verificar módulos do Apache
required_modules=("rewrite" "cgi")
for module in "${required_modules[@]}"; do
  if apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
    check_result 0 "Apache module enabled: $module"
  else
    check_result 1 "Apache module not enabled: $module"
  fi
done

# Verificar se o Nagios está acessível via web
if command -v curl &>/dev/null; then
  if curl -s -o /dev/null -w "%{http_code}" http://localhost/nagios/ | grep -q "401\|200"; then
    check_result 0 "Nagios web interface is accessible"
  else
    check_result 1 "Nagios web interface is not accessible"
  fi
else
  check_result 2 "curl not available - cannot test web interface"
fi

# === VERIFICAÇÃO DE CONECTIVIDADE ===

log_info "=== CONNECTIVITY CHECKS ==="

# Verificar conectividade com servidores monitorados
monitored_servers=(
  "10.101.150.66:SV01-Web"
  "10.101.150.67:SV02-OwnCloud"
)

for server_info in "${monitored_servers[@]}"; do
  ip=$(echo $server_info | cut -d':' -f1)
  name=$(echo $server_info | cut -d':' -f2)
  
  if ping -c 1 -W 3 $ip > /dev/null 2>&1; then
    check_result 0 "Connectivity to $name ($ip): OK"
    
    # Verificar NRPE se disponível
    if command -v /usr/lib/nagios/plugins/check_nrpe &>/dev/null; then
      if /usr/lib/nagios/plugins/check_nrpe -H $ip -c check_load > /dev/null 2>&1; then
        check_result 0 "NRPE connectivity to $name ($ip): OK"
      else
        check_result 2 "NRPE connectivity to $name ($ip): Failed"
      fi
    fi
  else
    check_result 1 "Connectivity to $name ($ip): Failed"
  fi
done

# === VERIFICAÇÃO DO FAIL2BAN ===

log_info "=== FAIL2BAN CHECKS ==="

# Verificar jails ativos
if command -v fail2ban-client &>/dev/null; then
  active_jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr -d ' \t')
  if [ -n "$active_jails" ]; then
    check_result 0 "Fail2Ban jails active: $active_jails"
    
    # Verificar cada jail
    for jail in $(echo $active_jails | tr ',' ' '); do
      jail_status=$(fail2ban-client status $jail 2>/dev/null | grep "Currently banned:" | awk '{print $3}')
      log_info "Jail $jail: $jail_status currently banned IPs"
    done
  else
    check_result 2 "No Fail2Ban jails are active"
  fi
else
  check_result 1 "Fail2Ban client not found"
fi

# === VERIFICAÇÃO DE LOGS ===

log_info "=== LOG CHECKS ==="

# Verificar logs do Nagios
nagios_log="/usr/local/nagios/var/nagios.log"
if [ -f "$nagios_log" ]; then
  check_result 0 "Nagios log file found"
  
  # Verificar se há erros recentes
  recent_errors=$(tail -100 "$nagios_log" | grep -i error | wc -l)
  if [ $recent_errors -eq 0 ]; then
    check_result 0 "No recent errors in Nagios log"
  else
    check_result 2 "Found $recent_errors recent errors in Nagios log"
  fi
else
  check_result 1 "Nagios log file not found"
fi

# Verificar logs do Apache
apache_error_log="/var/log/apache2/error.log"
if [ -f "$apache_error_log" ]; then
  check_result 0 "Apache error log found"
  
  # Verificar erros recentes
  recent_apache_errors=$(tail -100 "$apache_error_log" | grep -i error | wc -l)
  if [ $recent_apache_errors -eq 0 ]; then
    check_result 0 "No recent errors in Apache log"
  else
    check_result 2 "Found $recent_apache_errors recent errors in Apache log"
  fi
else
  check_result 2 "Apache error log not found"
fi

# === VERIFICAÇÃO DE RECURSOS ===

log_info "=== RESOURCE CHECKS ==="

# Verificar espaço em diretórios críticos
critical_dirs=(
  "/usr/local/nagios"
  "/var/log"
  "/tmp"
)

for dir in "${critical_dirs[@]}"; do
  if [ -d "$dir" ]; then
    dir_usage=$(df "$dir" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ $dir_usage -lt 80 ]; then
      check_result 0 "Directory $dir usage: ${dir_usage}% (normal)"
    elif [ $dir_usage -lt 90 ]; then
      check_result 2 "Directory $dir usage: ${dir_usage}% (warning)"
    else
      check_result 1 "Directory $dir usage: ${dir_usage}% (critical)"
    fi
  else
    check_result 1 "Critical directory not found: $dir"
  fi
done

# Verificar processos do Nagios
nagios_processes=$(pgrep -c nagios)
if [ $nagios_processes -gt 0 ]; then
  check_result 0 "Nagios processes running: $nagios_processes"
else
  check_result 1 "No Nagios processes found"
fi

# === VERIFICAÇÃO DE FIREWALL ===

log_info "=== FIREWALL CHECKS ==="

# Verificar UFW
if command -v ufw &>/dev/null; then
  ufw_status=$(ufw status | head -1)
  if echo "$ufw_status" | grep -q "active"; then
    check_result 0 "UFW firewall is active"
    
    # Verificar regras importantes
    if ufw status | grep -q "Apache"; then
      check_result 0 "Apache firewall rule found"
    else
      check_result 2 "Apache firewall rule not found"
    fi
  else
    check_result 2 "UFW firewall is not active"
  fi
else
  check_result 2 "UFW not installed"
fi

# === RESUMO FINAL ===

log_info "=== HEALTH CHECK SUMMARY ==="

log_info "Total checks performed: $total_checks"
log_success "Passed: $passed_checks"
log_warning "Warnings: $warning_checks"
log_error "Failed: $failed_checks"

# Calcular percentagem de sucesso
if [ $total_checks -gt 0 ]; then
  success_rate=$(( (passed_checks * 100) / total_checks ))
  log_info "Success rate: ${success_rate}%"
  
  if [ $failed_checks -eq 0 ] && [ $warning_checks -eq 0 ]; then
    log_success "ALL CHECKS PASSED - Nagios Core server is healthy!"
    exit 0
  elif [ $failed_checks -eq 0 ]; then
    log_warning "Some warnings found - Nagios Core server needs attention"
    exit 1
  else
    log_error "Critical issues found - Nagios Core server needs immediate attention"
    exit 2
  fi
else
  log_error "No checks were performed"
  exit 3
fi 