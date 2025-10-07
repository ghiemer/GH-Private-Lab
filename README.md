# 🚀 n8n Produktions-Deployment Anleitung

## 📋 Überblick

Dieses Setup erstellt eine vollständige Produktionsumgebung für n8n mit:
- **Ubuntu 24.04** als Zielserver
- **Caddy** als Reverse Proxy mit automatischem HTTPS (Let's Encrypt)
- **n8n** Container (neueste stabile Version)
- **PostgreSQL** Database mit persistenten Volumes
- **Docker Compose** für Orchestrierung
- **Automatische Backups** und Update-Skripte

## 🏗️ Architektur

```
Internet → Caddy (Port 80/443) → n8n (Port 5678) → PostgreSQL
```

### Services:
- `caddy`: Reverse Proxy mit automatischem HTTPS
- `n8n`: Workflow-Automation Platform
- `postgres`: PostgreSQL Database
- `mcp`: Platzhalter-Service für zukünftige MCP-Integration

### Volumes:
- `caddy-data`: Caddy Daten und Zertifikate
- `caddy-config`: Caddy Konfiguration
- `n8n-data`: n8n Workflows und Daten
- `postgres-data`: PostgreSQL Datenbank

## 🛠️ Installation

### 1. Server Vorbereitung (Ubuntu 24.04)

```bash
# System Updates
sudo apt update && sudo apt upgrade -y

# Docker Installation
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Docker Compose V2
sudo apt install docker-compose-plugin

# User zu Docker Gruppe hinzufügen
sudo usermod -aG docker $USER

# Neuanmeldung oder:
newgrp docker
```

### 2. Projekt Setup

```bash
# Repository klonen oder Dateien kopieren
mkdir -p /opt/n8n-production
cd /opt/n8n-production

# Dateien hierher kopieren:
# - docker-compose.yml
# - Caddyfile
# - .env.template
# - deploy.sh
# - backup.sh
```

### 3. Umgebungskonfiguration

```bash
# .env Datei erstellen
cp .env.template .env

# .env bearbeiten
nano .env
```

#### 🔧 Erforderliche Konfiguration in `.env`:

```bash
# Domain Setup
N8N_HOST=your-domain.com
WEBHOOK_URL=https://your-domain.com/

# Encryption Key generieren
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Database Password generieren
DB_POSTGRESDB_PASSWORD=$(openssl rand -base64 32)
```

### 4. DNS Konfiguration

Stelle sicher, dass deine Domain auf den Server zeigt:
```
A Record: your-domain.com → SERVER_IP
```

## 🚀 Deployment

### Automatisches Deployment

```bash
# Erstes Deployment
./deploy.sh deploy

# Updates mit Backup
./deploy.sh update
```

### Manuelle Schritte

```bash
# Images herunterladen
docker compose pull

# Services starten
docker compose up -d

# Status prüfen
docker compose ps
```

## 📊 Monitoring & Management

### Service Status prüfen
```bash
./deploy.sh status
```

### Logs anzeigen
```bash
./deploy.sh logs

# Oder spezifisch:
docker compose logs n8n
docker compose logs caddy
docker compose logs postgres
```

### Services neustarten
```bash
./deploy.sh restart

# Oder einzeln:
docker compose restart n8n
```

## 💾 Backup & Restore

### Automatisches Backup
```bash
# Backup erstellen
./deploy.sh backup

# Oder direkt:
./backup.sh
```

### Backup Inhalte
Das Backup erstellt:
- `postgres_TIMESTAMP.sql.gz`: PostgreSQL Dump
- `n8n_data_TIMESTAMP.tar.gz`: n8n Datenvolume
- `backup_TIMESTAMP.info`: Restore-Anweisungen

### Restore Process

#### 1. PostgreSQL Restore
```bash
# Backup entpacken und einspielen
gunzip -c postgres_20241007_120000.sql.gz | \
  docker exec -i postgres psql -U n8n -d n8n
```

#### 2. n8n Daten Restore
```bash
# Service stoppen
docker compose stop n8n

# Daten restore
docker run --rm \
  -v n8n-data:/data \
  -v $(pwd):/backup \
  alpine:latest \
  tar xzf /backup/n8n_data_20241007_120000.tar.gz -C /data

# Service starten
docker compose start n8n
```

## 🔄 Updates

### n8n Version Update
```bash
# Mit automatischem Backup
./deploy.sh update

# Oder manuell:
docker compose pull n8n
docker compose up -d n8n
```

### System Maintenance
```bash
# Docker aufräumen
docker system prune -f

# Alte Images entfernen
docker image prune -f

# Logs rotieren (falls nötig)
docker compose logs --tail=1000 > logs_backup.txt
```

## 🔒 Sicherheit

### Firewall Setup
```bash
# UFW aktivieren (falls nicht aktiv)
sudo ufw enable

# Nur notwendige Ports öffnen
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP (für Let's Encrypt)
sudo ufw allow 443/tcp  # HTTPS
```

### SSL/TLS
- Caddy verwaltet SSL-Zertifikate automatisch via Let's Encrypt
- Zertifikate werden automatisch erneuert
- HSTS und Security Headers sind konfiguriert

### Zusätzliche Sicherheit (Optional)
```bash
# n8n Basic Auth aktivieren (in .env):
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=secure_password
```

## 📈 Performance Tuning

### PostgreSQL Optimierung
Füge zu `docker-compose.yml` unter postgres → command hinzu:
```yaml
command: >
  postgres
  -c max_connections=200
  -c shared_buffers=256MB
  -c effective_cache_size=1GB
  -c maintenance_work_mem=64MB
  -c checkpoint_completion_target=0.9
  -c wal_buffers=16MB
  -c default_statistics_target=100
```

### n8n Speicher-Limits
```yaml
n8n:
  # ... andere Konfiguration
  deploy:
    resources:
      limits:
        memory: 2G
      reservations:
        memory: 1G
```

## 🧩 MCP Service Integration

Der Platzhalter `mcp` Service kann später konfiguriert werden:

```yaml
mcp:
  image: your-mcp-image:latest
  container_name: mcp
  restart: unless-stopped
  environment:
    - MCP_CONFIG=value
  volumes:
    - mcp-data:/data
  networks:
    - proxy
```

## 🆘 Troubleshooting

### Häufige Probleme

#### n8n startet nicht
```bash
# Logs prüfen
docker compose logs n8n

# Database Connection prüfen
docker compose exec postgres pg_isready -U n8n -d n8n
```

#### Let's Encrypt Fehler
```bash
# Caddy Logs prüfen
docker compose logs caddy

# DNS Resolution testen
nslookup your-domain.com

# Ports prüfen
sudo netstat -tlnp | grep :443
```

#### Slow Performance
```bash
# Ressourcenverbrauch prüfen
docker stats

# Disk Space prüfen
df -h
du -sh /var/lib/docker/
```

### Log Locations
- Caddy Access Logs: `/data/logs/n8n-access.log` (im caddy Container)
- n8n Logs: `docker compose logs n8n`
- PostgreSQL Logs: `docker compose logs postgres`

## 📞 Support

### Nützliche Commands
```bash
# Komplette Umgebung neustarten
docker compose down && docker compose up -d

# Alle Services und Volumes entfernen (ACHTUNG: Datenverlust!)
docker compose down -v

# System Info
docker system df
docker compose version
```

### Monitoring Setup (Optional)
Für Produktionsumgebungen empfohlen:
- **Uptime Kuma** für Service-Monitoring
- **Grafana + Prometheus** für Metriken
- **Loki** für Log-Aggregation

---

## 📝 Changelog

- **v1.0**: Initial setup mit Ubuntu 24.04, Caddy, n8n, PostgreSQL
- Automatische Backup- und Deployment-Skripte
- Vollständige Produktionskonfiguration mit Sicherheits-Headers
- MCP Service Vorbereitung
