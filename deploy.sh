#!/bin/bash

# DocPilot Shop - WordPress Deployment Script
# Usage: ./deploy.sh [start|stop|restart|update|logs|backup|restore]

set -e

COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="wp-site"
BACKUP_DIR="./backups"
NGINX_VHOST="/etc/nginx/sites-available/shop.docpilot.in"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root for nginx operations
check_nginx_perms() {
    if [ ! -w "/etc/nginx/sites-available" ] 2>/dev/null; then
        log_warn "Need sudo for nginx configuration. Run with sudo if needed."
    fi
}

# Deploy function
deploy() {
    log_info "Starting DocPilot Shop deployment..."
    
    # Check docker permissions
    if ! docker ps &>/dev/null; then
        log_error "Cannot connect to Docker daemon"
        log_info "Fix: sudo usermod -aG docker $USER && newgrp docker"
        log_info "Or run with: sudo ./deploy.sh start"
        exit 1
    fi
    
    # Pull latest images
    log_info "Pulling Docker images..."
    docker compose -f $COMPOSE_FILE pull
    
    # Start services
    log_info "Starting containers..."
    docker compose -f $COMPOSE_FILE up -d
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10
    
    # Check if containers are running
    if docker ps | grep -q "docpilot_shop_app"; then
        log_info "WordPress container is running"
    else
        log_error "WordPress container failed to start"
        docker compose -f $COMPOSE_FILE logs wordpress
        exit 1
    fi
    
    if docker ps | grep -q "docpilot_shop_db"; then
        log_info "Database container is running"
    else
        log_error "Database container failed to start"
        docker compose -f $COMPOSE_FILE logs db
        exit 1
    fi
    
    # Display volume location
    log_info "WordPress files location:"
    docker volume inspect ${PROJECT_NAME}_docpilot_shop_data --format '{{ .Mountpoint }}'
    
    log_info "Deployment complete!"
    log_info "Next steps:"
    echo "  1. Configure nginx vhost (see shop.docpilot.in.conf)"
    echo "  2. Test nginx config: sudo nginx -t"
    echo "  3. Reload nginx: sudo systemctl reload nginx"
    echo "  4. Visit: http://shop.docpilot.in"
}

# Stop function
stop() {
    log_info "Stopping DocPilot Shop..."
    docker compose -f $COMPOSE_FILE down
    log_info "Stopped"
}

# Restart function
restart() {
    log_info "Restarting DocPilot Shop..."
    docker compose -f $COMPOSE_FILE restart
    log_info "Restarted"
}

# Update function
update() {
    log_info "Updating DocPilot Shop..."
    docker compose -f $COMPOSE_FILE pull
    docker compose -f $COMPOSE_FILE up -d
    log_info "Updated"
}

# Logs function
logs() {
    docker compose -f $COMPOSE_FILE logs -f
}

# Backup function
backup() {
    log_info "Creating backup..."
    
    mkdir -p $BACKUP_DIR
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/docpilot_shop_backup_$TIMESTAMP.sql"
    
    # Backup database
    log_info "Backing up database..."
    docker exec docpilot_shop_db mysqldump -u wpuser -pwppass wpdb > "$BACKUP_FILE"
    
    if [ -f "$BACKUP_FILE" ]; then
        log_info "Database backup created: $BACKUP_FILE"
        
        # Compress backup
        gzip "$BACKUP_FILE"
        log_info "Compressed to: ${BACKUP_FILE}.gz"
    else
        log_error "Backup failed!"
        exit 1
    fi
    
    # Backup WordPress files
    log_info "Backing up WordPress files..."
    docker run --rm \
        -v ${PROJECT_NAME}_docpilot_shop_data:/source:ro \
        -v $(pwd)/$BACKUP_DIR:/backup \
        alpine \
        tar czf /backup/docpilot_shop_files_$TIMESTAMP.tar.gz -C /source .
    
    log_info "Files backup created: $BACKUP_DIR/docpilot_shop_files_$TIMESTAMP.tar.gz"
    log_info "Backup complete!"
}

# Restore function
restore() {
    if [ -z "$2" ]; then
        log_error "Usage: ./deploy.sh restore <backup_file.sql.gz>"
        exit 1
    fi
    
    BACKUP_FILE="$2"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    log_warn "This will restore database from: $BACKUP_FILE"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    log_info "Restoring database..."
    gunzip -c "$BACKUP_FILE" | docker exec -i docpilot_shop_db mysql -u wpuser -pwppass wpdb
    
    log_info "Restore complete!"
}

# Status function
status() {
    log_info "DocPilot Shop Status:"
    echo ""
    docker compose -f $COMPOSE_FILE ps
    echo ""
    log_info "Volumes:"
    docker volume ls | grep docpilot_shop
    echo ""
    log_info "Network:"
    docker network ls | grep docpilot_shop
}

# Setup nginx function
setup_nginx() {
    check_nginx_perms
    
    log_info "Creating nginx vhost configuration..."
    
    if [ -f "$NGINX_VHOST" ]; then
        log_warn "Nginx vhost already exists at $NGINX_VHOST"
        read -p "Overwrite? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Skipping nginx setup"
            return
        fi
    fi
    
    # Get volume mount point
    VOLUME_PATH=$(docker volume inspect ${PROJECT_NAME}_docpilot_shop_data --format '{{ .Mountpoint }}' 2>/dev/null || echo "/var/lib/docker/volumes/${PROJECT_NAME}_docpilot_shop_data/_data")
    
    log_info "Creating nginx configuration at: shop.docpilot.in.conf"
    log_info "Volume path: $VOLUME_PATH"
    log_warn "You'll need to copy this to $NGINX_VHOST with sudo"
}

# Setup SSL with Certbot
setup_ssl() {
    log_info "Setting up SSL certificate with Certbot..."
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot is not installed!"
        log_info "Install it with: sudo apt install certbot python3-certbot-nginx"
        exit 1
    fi
    
    # Check if nginx config exists
    if [ ! -f "/etc/nginx/sites-enabled/shop.docpilot.in" ]; then
        log_error "Nginx vhost not found in /etc/nginx/sites-enabled/"
        log_info "Please run: sudo cp shop.docpilot.in.conf /etc/nginx/sites-available/"
        log_info "Then: sudo ln -s /etc/nginx/sites-available/shop.docpilot.in.conf /etc/nginx/sites-enabled/"
        exit 1
    fi
    
    # Verify nginx config
    log_info "Testing nginx configuration..."
    if ! sudo nginx -t; then
        log_error "Nginx configuration test failed!"
        exit 1
    fi
    
    # Reload nginx
    log_info "Reloading nginx..."
    sudo systemctl reload nginx
    
    # Get email for certbot
    read -p "Enter your email for Let's Encrypt notifications: " EMAIL
    
    if [ -z "$EMAIL" ]; then
        log_error "Email is required"
        exit 1
    fi
    
    # Run certbot
    log_info "Running Certbot for shop.docpilot.in..."
    sudo certbot --nginx \
        -d shop.docpilot.in \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
    
    if [ $? -eq 0 ]; then
        log_info "SSL certificate installed successfully!"
        log_info "Your site is now available at: https://shop.docpilot.in"
        log_info "Certificate will auto-renew via certbot timer"
        
        # Test auto-renewal
        log_info "Testing certificate renewal..."
        sudo certbot renew --dry-run
    else
        log_error "Certbot failed! Check the logs above."
        exit 1
    fi
}

# Renew SSL certificate
renew_ssl() {
    log_info "Renewing SSL certificates..."
    
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot is not installed!"
        exit 1
    fi
    
    sudo certbot renew
    
    if [ $? -eq 0 ]; then
        log_info "Certificate renewal successful!"
        sudo systemctl reload nginx
    else
        log_error "Certificate renewal failed!"
        exit 1
    fi
}

# Main script logic
case "${1:-start}" in
    start|deploy)
        deploy
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    update)
        update
        ;;
    logs)
        logs
        ;;
    backup)
        backup
        ;;
    restore)
        restore "$@"
        ;;
    status)
        status
        ;;
    nginx)
        setup_nginx
        ;;
    ssl|certbot)
        setup_ssl
        ;;
    ssl-renew)
        renew_ssl
        ;;
    *)
        echo "DocPilot Shop - Deployment Script"
        echo ""
        echo "Usage: ./deploy.sh [command]"
        echo ""
        echo "Commands:"
        echo "  start|deploy  - Deploy and start the application (default)"
        echo "  stop          - Stop the application"
        echo "  restart       - Restart the application"
        echo "  update        - Pull latest images and restart"
        echo "  logs          - Show and follow logs"
        echo "  backup        - Create database and files backup"
        echo "  restore FILE  - Restore database from backup"
        echo "  status        - Show application status"
        echo "  nginx         - Show nginx setup info"
        echo "  ssl|certbot   - Setup SSL certificate with Let's Encrypt"
        echo "  ssl-renew     - Manually renew SSL certificate"
        echo ""
        exit 1
        ;;
esac
