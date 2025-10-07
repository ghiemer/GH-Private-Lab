#!/bin/bash

# =============================================================================
# n8n Deployment Script
# =============================================================================
# Automatisiert das Deployment und Updates von n8n

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funktionen
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Prüfe ob .env existiert
check_env() {
    if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
        log_error ".env file not found!"
        log_info "Please copy .env.template to .env and configure your settings:"
        log_info "cp .env.template .env"
        exit 1
    fi
}

# Prüfe erforderliche Umgebungsvariablen
check_required_vars() {
    source "${SCRIPT_DIR}/.env"
    
    local required_vars=(
        "N8N_HOST"
        "N8N_ENCRYPTION_KEY"
        "DB_POSTGRESDB_PASSWORD"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        log_info "Please configure these variables in your .env file"
        exit 1
    fi
}

# Erstelle Backup vor Update
create_backup() {
    log_info "Creating backup before deployment..."
    if [[ -f "${SCRIPT_DIR}/backup.sh" ]]; then
        "${SCRIPT_DIR}/backup.sh"
        log_success "Backup completed"
    else
        log_warning "backup.sh not found, skipping backup"
    fi
}

# Pull neueste Images
pull_images() {
    log_info "Pulling latest Docker images..."
    docker compose pull
    log_success "Images updated"
}

# Starte Services
start_services() {
    log_info "Starting services..."
    docker compose up -d
    log_success "Services started"
}

# Prüfe Service Health
check_health() {
    log_info "Checking service health..."
    
    # Warte auf Services
    sleep 10
    
    # Prüfe PostgreSQL
    if docker compose exec postgres pg_isready -U "${DB_POSTGRESDB_USER:-n8n}" -d "${DB_POSTGRESDB_DATABASE:-n8n}" > /dev/null 2>&1; then
        log_success "PostgreSQL is healthy"
    else
        log_error "PostgreSQL health check failed"
        return 1
    fi
    
    # Prüfe n8n
    if docker compose exec n8n wget --no-verbose --tries=1 --spider http://localhost:5678/healthz > /dev/null 2>&1; then
        log_success "n8n is healthy"
    else
        log_error "n8n health check failed"
        return 1
    fi
    
    # Prüfe Caddy
    if docker compose exec caddy caddy list > /dev/null 2>&1; then
        log_success "Caddy is healthy"
    else
        log_error "Caddy health check failed"
        return 1
    fi
}

# Zeige Service Status
show_status() {
    echo ""
    log_info "Service Status:"
    docker compose ps
    
    echo ""
    log_info "Access your n8n instance at:"
    source "${SCRIPT_DIR}/.env"
    echo "🌐 https://${N8N_HOST}"
}

# Hauptfunktion
main() {
    local action="${1:-deploy}"
    
    cd "${SCRIPT_DIR}"
    
    case "$action" in
        "deploy"|"update")
            log_info "🚀 Starting n8n deployment..."
            check_env
            check_required_vars
            
            if [[ "$action" == "update" ]]; then
                create_backup
            fi
            
            pull_images
            start_services
            
            log_info "Waiting for services to start..."
            sleep 15
            
            if check_health; then
                show_status
                log_success "🎉 Deployment completed successfully!"
            else
                log_error "🚨 Deployment completed but some health checks failed"
                log_info "Check logs with: docker compose logs"
                exit 1
            fi
            ;;
        "backup")
            log_info "🗄️  Creating backup..."
            create_backup
            ;;
        "logs")
            docker compose logs -f
            ;;
        "stop")
            log_info "🛑 Stopping services..."
            docker compose stop
            log_success "Services stopped"
            ;;
        "restart")
            log_info "🔄 Restarting services..."
            docker compose restart
            log_success "Services restarted"
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Usage: $0 {deploy|update|backup|logs|stop|restart|status}"
            echo ""
            echo "Commands:"
            echo "  deploy  - Initial deployment (default)"
            echo "  update  - Update with backup"
            echo "  backup  - Create backup only"
            echo "  logs    - Show service logs"
            echo "  stop    - Stop all services"
            echo "  restart - Restart all services"
            echo "  status  - Show service status"
            exit 1
            ;;
    esac
}

# Ausführen
main "$@"