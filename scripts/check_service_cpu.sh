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