# 🚀 n8n Production Deployment Guide

## 📋 Overview

This setup creates a complete production environment for n8n with:
- **Ubuntu 24.04** as target server
- **Caddy** as reverse proxy with automatic HTTPS (Let's Encrypt)
- **n8n** container (latest stable version)
- **PostgreSQL** database with persistent volumes
- **Docker Compose** for orchestration
- **Automated backups** and update scripts

## 🏗️ Architecture

```
Internet → Caddy (Port 80/443) → n8n (Port 5678) → PostgreSQL
```

### Services:
- `caddy`: Reverse proxy with automatic HTTPS
- `n8n`: Workflow automation platform
- `postgres`: PostgreSQL database
- `mcp`: Placeholder service for future MCP integration

### Volumes:
- `caddy-data`: Caddy data and certificates
- `caddy-config`: Caddy configuration
- `n8n-data`: n8n workflows and data
- `postgres-data`: PostgreSQL database

## 🛠️ Installation

### 1. Server Preparation (Ubuntu 24.04)

```bash
# System updates
sudo apt update && sudo apt upgrade -y

# Docker installation
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Docker Compose V2
sudo apt install docker-compose-plugin

# Add user to Docker group
sudo usermod -aG docker $USER

# Re-login or:
newgrp docker
```

### 2. Project Setup

```bash
# Clone repository or copy files
mkdir -p /opt/n8n-production
cd /opt/n8n-production

# Copy files here:
# - docker-compose.yml
# - Caddyfile
# - .env.example
# - deploy.sh
# - backup.sh
```

### 3. Environment Configuration

```bash
# Create .env file
cp .env.example .env

# Edit .env
nano .env
```

### 4. Caddyfile Configuration

⚠️ **Important**: Adapt the `Caddyfile` to your domain:

```bash
# Edit Caddyfile
nano Caddyfile
```

Replace in the file:
- `your-domain.com` → your actual domain
- `your-email@example.com` → your email address for Let's Encrypt

#### 🔧 Required configuration in `.env`:

```bash
# Domain setup
N8N_HOST=your-domain.com
WEBHOOK_URL=https://your-domain.com/

# Generate encryption key
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Generate database password
DB_POSTGRESDB_PASSWORD=$(openssl rand -base64 32)
```

### 5. DNS Configuration

Make sure your domain points to the server:
```
A Record: your-domain.com → SERVER_IP
```

## 🚀 Deployment

### Automatic Deployment

```bash
# Initial deployment
./deploy.sh deploy

# Updates with backup
./deploy.sh update
```

### Manual Steps

```bash
# Download images
docker compose pull

# Start services
docker compose up -d

# Check status
docker compose ps
```

## 📊 Monitoring & Management

### Check service status
```bash
./deploy.sh status
```

### View logs
```bash
./deploy.sh logs

# Or specifically:
docker compose logs n8n
docker compose logs caddy
docker compose logs postgres
```

### Restart services
```bash
./deploy.sh restart

# Or individually:
docker compose restart n8n
```

## 💾 Backup & Restore

### Automatic Backup
```bash
# Create backup
./deploy.sh backup

# Or directly:
./backup.sh
```

### Backup Contents
The backup creates:
- `postgres_TIMESTAMP.sql.gz`: PostgreSQL dump
- `n8n_data_TIMESTAMP.tar.gz`: n8n data volume
- `backup_TIMESTAMP.info`: Restore instructions

### Restore Process

#### 1. PostgreSQL Restore
```bash
# Extract and restore backup
gunzip -c postgres_20241007_120000.sql.gz | \
  docker exec -i postgres psql -U n8n -d n8n
```

#### 2. n8n Data Restore
```bash
# Stop service
docker compose stop n8n

# Restore data
docker run --rm \
  -v n8n-data:/data \
  -v $(pwd):/backup \
  alpine:latest \
  tar xzf /backup/n8n_data_20241007_120000.tar.gz -C /data

# Start service
docker compose start n8n
```

## 🔄 Updates

### n8n Version Update
```bash
# With automatic backup
./deploy.sh update

# Or manually:
docker compose pull n8n
docker compose up -d n8n
```

### System Maintenance
```bash
# Clean up Docker
docker system prune -f

# Remove old images
docker image prune -f

# Rotate logs (if needed)
docker compose logs --tail=1000 > logs_backup.txt
```

## 🔒 Security

### Firewall Setup
```bash
# Enable UFW (if not active)
sudo ufw enable

# Open only necessary ports
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP (for Let's Encrypt)
sudo ufw allow 443/tcp  # HTTPS
```

### SSL/TLS
- Caddy manages SSL certificates automatically via Let's Encrypt
- Certificates are automatically renewed
- HSTS and security headers are configured

### Additional Security (Optional)
```bash
# Enable n8n Basic Auth (in .env):
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=secure_password
```

## 📈 Performance Tuning

### PostgreSQL Optimization
Add to `docker-compose.yml` under postgres → command:
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

### n8n Memory Limits
```yaml
n8n:
  # ... other configuration
  deploy:
    resources:
      limits:
        memory: 2G
      reservations:
        memory: 1G
```

## 🧩 MCP Service Integration

The placeholder `mcp` service can be configured later:

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

### Common Issues

#### n8n won't start
```bash
# Check logs
docker compose logs n8n

# Check database connection
docker compose exec postgres pg_isready -U n8n -d n8n
```

#### Let's Encrypt errors
```bash
# Check Caddy logs
docker compose logs caddy

# Test DNS resolution
nslookup your-domain.com

# Check ports
sudo netstat -tlnp | grep :443
```

#### Slow Performance
```bash
# Check resource usage
docker stats

# Check disk space
df -h
du -sh /var/lib/docker/
```

### Log Locations
- Caddy Access Logs: `/data/logs/n8n-access.log` (in caddy container)
- n8n Logs: `docker compose logs n8n`
- PostgreSQL Logs: `docker compose logs postgres`

## 📞 Support

### Useful Commands
```bash
# Restart complete environment
docker compose down && docker compose up -d

# Remove all services and volumes (WARNING: Data loss!)
docker compose down -v

# System info
docker system df
docker compose version
```

### Monitoring Setup (Optional)
Recommended for production environments:
- **Uptime Kuma** for service monitoring
- **Grafana + Prometheus** for metrics
- **Loki** for log aggregation

---

## 📝 Changelog

- **v1.0**: Initial setup with Ubuntu 24.04, Caddy, n8n, PostgreSQL
- Automated backup and deployment scripts
- Complete production configuration with security headers
- MCP service preparation
