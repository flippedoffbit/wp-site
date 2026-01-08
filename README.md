# WordPress Docker Setup

Secure, containerized WordPress deployment with nginx reverse proxy.

## Features

- 🔒 **Security Hardened**: Read-only filesystem, minimal capabilities, no privilege escalation
- 🐳 **Docker Compose**: Easy deployment and management
- 🌐 **Nginx Reverse Proxy**: Host nginx handles SSL/internet exposure
- 📦 **Apache + WordPress**: Full-featured WordPress with PHP 8.2
- 🔐 **Environment Variables**: No hardcoded secrets
- 💾 **Automated Backups**: Built-in backup/restore scripts
- 📊 **Resource Limits**: CPU and memory capped
- 🛡️ **SSL Support**: Let's Encrypt integration via Certbot

## Architecture

```
Internet → Host Nginx (Port 80/443) → Docker Container (Apache:8080) → MariaDB
```

## Security Features

- Read-only root filesystem
- Minimal Linux capabilities (only SETGID, SETUID)
- No new privileges allowed
- Resource constraints (1 CPU, 512MB RAM)
- Network isolation
- Port binding to localhost only
- Separated tmpfs mounts

## Quick Start

### 1. Prerequisites

- Docker & Docker Compose
- Nginx (on host)
- Domain pointing to server IP

### 2. Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit with your values
nano .env
```

**Required variables:**
```env
MYSQL_DATABASE=wpdb
MYSQL_USER=wpuser
MYSQL_PASSWORD=your_secure_password_here
MYSQL_ROOT_PASSWORD=your_secure_root_password_here
DOMAIN=shop.example.com
```

### 3. Deploy

```bash
# Make deploy script executable
chmod +x deploy.sh

# Start WordPress
./deploy.sh start

# Copy nginx config
sudo cp shop.docpilot.in.conf /etc/nginx/sites-available/your-domain.conf
sudo ln -s /etc/nginx/sites-available/your-domain.conf /etc/nginx/sites-enabled/

# Update domain in nginx config
sudo nano /etc/nginx/sites-available/your-domain.conf
# Change: server_name shop.docpilot.in; → server_name your-domain.com;

# Test and reload nginx
sudo nginx -t
sudo systemctl reload nginx
```

### 4. Setup SSL (Optional but Recommended)

```bash
./deploy.sh ssl
```

## Management Commands

```bash
./deploy.sh start      # Deploy and start
./deploy.sh stop       # Stop containers
./deploy.sh restart    # Restart containers
./deploy.sh logs       # View logs
./deploy.sh status     # Check status
./deploy.sh backup     # Backup database and files
./deploy.sh restore    # Restore from backup
./deploy.sh ssl        # Setup SSL certificate
./deploy.sh ssl-renew  # Renew SSL certificate
```

## File Structure

```
.
├── docker-compose.yml        # Container definitions
├── deploy.sh                 # Deployment script
├── shop.docpilot.in.conf    # Nginx configuration template
├── wp-php.ini               # PHP configuration
├── .env                     # Environment variables (create from .env.example)
└── backups/                 # Backup storage (auto-created)
```

## Security Considerations

### Host Safety: ✅ Excellent (8.5/10)
- Container escape: Very difficult
- Filesystem isolation: Protected
- Privilege escalation: Blocked
- Resource exhaustion: Prevented

### Application Safety: ⚠️ Moderate
- WordPress files are writable (for plugin/theme updates)
- Consider disabling file modifications in production:
  ```php
  define('DISALLOW_FILE_EDIT', true);
  define('DISALLOW_FILE_MODS', true);
  ```

## Customization

### PHP Settings
Edit `wp-php.ini` to adjust PHP configuration.

### Resource Limits
Edit `docker-compose.yml`:
```yaml
deploy:
  resources:
    limits:
      cpus: "2.0"
      memory: 1G
```

### Container Names
Update `container_name` fields in `docker-compose.yml` to match your project.

## Backup & Restore

### Automatic Backup
```bash
./deploy.sh backup
```
Creates timestamped backups in `./backups/`:
- Database SQL dump (compressed)
- WordPress files tarball

### Restore
```bash
./deploy.sh restore ./backups/backup_file.sql.gz
```

## Troubleshooting

### Containers not starting
```bash
docker compose logs wordpress
docker compose logs db
```

### Permission denied errors
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### Site not accessible
```bash
# Check containers
docker ps | grep docpilot_shop

# Check nginx
sudo nginx -t
sudo systemctl status nginx

# Check logs
sudo tail -f /var/log/nginx/your-domain.error.log
```

## Ports

- **8080**: WordPress container (bound to 127.0.0.1 only)
- **3306**: MariaDB (internal network only)
- **80/443**: Host nginx (public-facing)

## Volumes

- `docpilot_shop_data`: WordPress files
- `docpilot_shop_db`: MariaDB database

## Network

All containers on isolated bridge network `docpilot_shop_net`.

## Production Checklist

- [ ] Change all passwords in `.env`
- [ ] Update domain in nginx config
- [ ] Setup SSL certificate
- [ ] Configure WordPress (disable file editor)
- [ ] Setup automated backups (cron)
- [ ] Enable WordPress auto-updates
- [ ] Install security plugins (Wordfence, etc.)
- [ ] Configure fail2ban for brute force protection

## License

MIT

## Contributing

Pull requests welcome! Please maintain the security-focused approach.
