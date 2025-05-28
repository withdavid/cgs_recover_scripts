# CGS Recovery Scripts

Sistema de scripts automatizados para deployment e recuperação de servidores CGS (Configuração e Gestão de Sistemas).

## 📋 Visão Geral

Este projeto contém scripts de deployment automatizado para três servidores:

- **Server 1 (SV01 - 10.101.150.66)**: Servidor Web/DNS com Nginx e BIND9
- **Server 2 (SV02 - 10.101.150.67)**: Servidor OwnCloud com MariaDB e Samba
- **Server 3 (SV03 - 10.101.150.68)**: Servidor de Monitoramento Nagios Core

## 🏗️ Arquitetura do Sistema

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Server 1      │    │   Server 2      │    │   Server 3      │
│   (Web/DNS)     │    │(OwnCloud + SMB) │    │   (Monitoring)  │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • Nginx         │    │ • Apache2       │    │ • Nagios Core   │
│ • BIND9 DNS     │    │ • OwnCloud      │    │ • NRPE Client   │
│ • NRPE Agent    │    │ • MariaDB       │    │ • Fail2Ban      │
│ • Fail2Ban      │    │ • Samba         │    │ • UFW Firewall  │
│ • UFW Firewall  │    │ • UFW Firewall  │    └─────────────────┘
└─────────────────┘    │ • NRPE Agent    │    
                       │ • Fail2Ban      │
                       └─────────────────┘
```

## 📁 Estrutura do Projeto

```
cgs_recover_scripts/
├── README.md                   
├── deploy_sv1.sh               # Script de deployment Server 1
├── deploy_sv2.sh               # Script de deployment Server 2
├── deploy_sv3.sh               # Script de deployment Server 3
├── health_check_sv1.sh         # Health check Server 1
├── health_check_sv2.sh         # Health check Server 2
├── health_check_sv3.sh         # Health check Server 3
├── conf/                       # Arquivos de configuração
│   ├── server01_*.conf         # Configurações Server 1
│   ├── server02_*.conf         # Configurações Server 2
│   └── server03_*.conf         # Configurações Server 3
└── scripts/                    # Scripts de monitoramento
    ├── check_smb_share         # Verificação Samba
    ├── check_locks.sh          # Verificação de locks
    └── check_service_cpu.sh    # Verificação CPU serviços
```

## 🚀 Instalação e Uso

### Pré-requisitos

- Ubuntu 22.04 LTS ou Ubuntu 24.04 LTS
- Acesso root ou sudo

### Deployment dos Servidores

#### Server 1 (Web/DNS)
```bash
# Clonar o repositório
git clone <repository-url>
cd cgs_recover_scripts

# Executar deployment
sudo ./deploy_sv1.sh

# Verificar saúde do sistema
sudo ./health_check_sv1.sh
```

#### Server 2 (OwnCloud)
```bash
# Executar deployment
sudo ./deploy_sv2.sh

# Verificar saúde do sistema
sudo ./health_check_sv2.sh
```

#### Server 3 (Nagios)
```bash
# Executar deployment
sudo ./deploy_sv3.sh

# Verificar saúde do sistema
sudo ./health_check_sv3.sh
```
