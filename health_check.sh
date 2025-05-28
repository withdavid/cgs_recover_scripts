#!/usr/bin/env bash
set -uo pipefail

# ===============================
# Health Check Script
# Verifica o estado de todos os serviços e configurações
# ===============================

# Cores para saída
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Variáveis de status
STATUS_OK=0
STATUS_WARNING=0
STATUS_ERROR=0

# Diretórios de configuração
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONF_DIR="${BASE_DIR}/conf"

# Função para exibir resultados
print_status() {
  local service=$1
  local status=$2
  local message=$3
  
  if [ "$status" = "OK" ]; then
    echo -e "${GREEN}[OK]${NC} $service: $message"
    STATUS_OK=$((STATUS_OK+1))
  elif [ "$status" = "WARNING" ]; then
    echo -e "${YELLOW}[WARNING]${NC} $service: $message"
    STATUS_WARNING=$((STATUS_WARNING+1))
  else
    echo -e "${RED}[ERROR]${NC} $service: $message"
    STATUS_ERROR=$((STATUS_ERROR+1))
  fi
}

# Verifica se o script está sendo executado como root
if [[ $(id -u) -ne 0 ]]; then
  echo -e "${RED}Este script precisa ser executado como root.${NC}" >&2
  exit 1
fi

echo "======================= VERIFICAÇÃO DE SAÚDE DO SISTEMA ======================="
echo "Iniciando verificação em $(date)"
echo "=========================================================================="

# 1. Verificar BIND (DNS)
echo -e "\n${YELLOW}Verificando BIND...${NC}"

# Verifica se o serviço está rodando
if systemctl is-active --quiet bind9 || systemctl is-active --quiet named; then
  print_status "BIND" "OK" "Serviço está rodando"
else
  print_status "BIND" "ERROR" "Serviço não está rodando"
fi

# Verifica arquivos de configuração
if [[ -f "/etc/bind/named.conf.local" && -s "/etc/bind/named.conf.local" ]]; then
  print_status "BIND" "OK" "Arquivo de configuração named.conf.local existe e não está vazio"
else
  print_status "BIND" "ERROR" "Arquivo de configuração named.conf.local não existe ou está vazio"
fi

if [[ -f "/etc/bind/db.cgs6.local" && -s "/etc/bind/db.cgs6.local" ]]; then
  print_status "BIND" "OK" "Arquivo de configuração db.cgs6.local existe e não está vazio"
else
  print_status "BIND" "ERROR" "Arquivo de configuração db.cgs6.local não existe ou está vazio"
fi

# Teste funcional DNS
if command -v dig &>/dev/null; then
  if dig @localhost cgs6.local &>/dev/null; then
    print_status "BIND" "OK" "Resolução DNS funcionando para cgs6.local"
  else
    print_status "BIND" "WARNING" "Falha na resolução DNS para cgs6.local"
  fi
else
  print_status "BIND" "WARNING" "Comando 'dig' não encontrado, não foi possível testar DNS"
fi

# 2. Verificar NGINX
echo -e "\n${YELLOW}Verificando NGINX...${NC}"

# Verifica se o serviço está rodando
if systemctl is-active --quiet nginx; then
  print_status "NGINX" "OK" "Serviço está rodando"
else
  print_status "NGINX" "ERROR" "Serviço não está rodando"
fi

# Verificação simples do servidor web
if command -v curl &>/dev/null; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null)
  if [[ "$HTTP_CODE" =~ ^(200|301|302|303|307|308)$ ]]; then
    print_status "NGINX" "OK" "Servidor web respondendo com código HTTP $HTTP_CODE"
  else
    print_status "NGINX" "WARNING" "Servidor web respondendo com código HTTP inesperado: $HTTP_CODE"
  fi
else
  print_status "NGINX" "WARNING" "Comando 'curl' não encontrado, não foi possível testar o servidor web"
fi

# 3. Verificar Fail2Ban
echo -e "\n${YELLOW}Verificando Fail2Ban...${NC}"

# Verifica se o serviço está rodando
if systemctl is-active --quiet fail2ban; then
  print_status "Fail2Ban" "OK" "Serviço está rodando"
else
  print_status "Fail2Ban" "ERROR" "Serviço não está rodando"
fi

# Verifica arquivos de configuração
if [[ -f "/etc/fail2ban/jail.local" && -s "/etc/fail2ban/jail.local" ]]; then
  print_status "Fail2Ban" "OK" "Arquivo jail.local existe e não está vazio"
else
  print_status "Fail2Ban" "ERROR" "Arquivo jail.local não existe ou está vazio"
fi

# Verifica status das jails
if command -v fail2ban-client &>/dev/null; then
  JAIL_STATUS=$(fail2ban-client status 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    JAIL_COUNT=$(fail2ban-client status | grep "Jail list" | awk -F':' '{print $2}' | tr ',' '\n' | grep -v "^\s*$" | wc -l)
    if [[ $JAIL_COUNT -gt 0 ]]; then
      print_status "Fail2Ban" "OK" "$JAIL_COUNT jails configuradas e ativas"
    else
      print_status "Fail2Ban" "WARNING" "Nenhuma jail está ativa"
    fi
  else
    print_status "Fail2Ban" "ERROR" "Erro ao consultar status das jails"
  fi
else
  print_status "Fail2Ban" "WARNING" "Comando fail2ban-client não encontrado"
fi

# 4. Verificar NRPE
echo -e "\n${YELLOW}Verificando NRPE...${NC}"

# Verifica se o serviço está rodando
if systemctl is-active --quiet nrpe || ps aux | grep -v grep | grep -q nrpe; then
  print_status "NRPE" "OK" "Serviço está rodando"
else
  print_status "NRPE" "WARNING" "Serviço não parece estar rodando"
fi

# Verifica configuração
NRPE_CONFIG="/usr/local/nagios/etc/nrpe.cfg"
if [[ -f "$NRPE_CONFIG" && -s "$NRPE_CONFIG" ]]; then
  print_status "NRPE" "OK" "Arquivo de configuração existe e não está vazio"
else
  print_status "NRPE" "ERROR" "Arquivo de configuração não existe ou está vazio"
fi

# Verifica plugins personalizados
PLUGINS_DIR="/usr/local/nagios/libexec"
for plugin in check_service_cpu.sh check_locks.sh; do
  if [[ -f "${PLUGINS_DIR}/${plugin}" && -x "${PLUGINS_DIR}/${plugin}" ]]; then
    print_status "NRPE" "OK" "Plugin $plugin existe e é executável"
  else
    print_status "NRPE" "ERROR" "Plugin $plugin não existe ou não é executável"
  fi
done

# 5. Verificar UFW
echo -e "\n${YELLOW}Verificando UFW...${NC}"

# Verifica se o UFW está ativo
if command -v ufw &>/dev/null; then
  UFW_STATUS=$(ufw status | grep -i "Status:" | awk '{print $2}')
  if [[ "$UFW_STATUS" == "active" ]]; then
    print_status "UFW" "OK" "Firewall está ativo"
    
    # Verifica regras específicas
    REQUIRED_PORTS=("22/tcp" "80/tcp" "443/tcp" "53/tcp" "53/udp" "5666/tcp")
    for port in "${REQUIRED_PORTS[@]}"; do
      if ufw status | grep -q "$port"; then
        print_status "UFW" "OK" "Regra para $port está configurada"
      else
        print_status "UFW" "WARNING" "Regra para $port não encontrada"
      fi
    done
  else
    print_status "UFW" "ERROR" "Firewall não está ativo"
  fi
else
  print_status "UFW" "ERROR" "UFW não está instalado"
fi

# Resumo
echo -e "\n${YELLOW}Resumo da verificação:${NC}"
echo "=========================================================================="
echo -e "${GREEN}$STATUS_OK${NC} verificações bem-sucedidas"
echo -e "${YELLOW}$STATUS_WARNING${NC} avisos"
echo -e "${RED}$STATUS_ERROR${NC} erros"
echo "=========================================================================="

if [[ $STATUS_ERROR -gt 0 ]]; then
  echo -e "${RED}ATENÇÃO: Existem erros que precisam ser corrigidos!${NC}"
  exit 1
elif [[ $STATUS_WARNING -gt 0 ]]; then
  echo -e "${YELLOW}ATENÇÃO: Existem avisos que podem precisar de atenção!${NC}"
  exit 0
else
  echo -e "${GREEN}SUCESSO: Todos os serviços e configurações estão funcionando corretamente!${NC}"
  exit 0
fi 