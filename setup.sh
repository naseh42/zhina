#!/bin/bash
set -euo pipefail
exec > >(tee -a "/var/log/zhinainstall.log") 2>&1

INSTALL_DIR="/var/lib/zhinapanel"
CONFIG_DIR="/etc/zhinapanel"
LOG_DIR="/var/log/zhinapanel"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
SERVICE_USER="zhinapanel"
DB_NAME="zhinapanel_db"
DB_USER="zhinapanel_user"
PANEL_PORT=8001
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -hex 8)
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
XRAY_HTTP_PORT=8080
DB_PASSWORD=$(openssl rand -hex 16)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { 
    echo -e "${RED}[✗] $1${NC}" >&2
    echo -e "For full error details, check the log file: ${YELLOW}/var/log/zhinainstall.log${NC}"
    exit 1
}
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }
warning() { echo -e "${YELLOW}[!] $1${NC}"; }

check_system() {
    info "Checking system prerequisites..."
    [[ $EUID -ne 0 ]] && error "This script requires root access"
    if [[ ! -f /etc/os-release ]]; then
        error "Unknown operating system"
    fi
    source /etc/os-release
    [[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && 
        warning "This script has been tested on Ubuntu/Debian only"
    success "System check completed"
}

install_prerequisites() {
    info "Installing necessary packages..."
    apt-get update -y || error "Error updating package list"
    apt-get install -y \
        git python3 python3-venv python3-pip \
        postgresql postgresql-contrib nginx \
        curl wget openssl unzip uuid-runtime \
        certbot python3-certbot-nginx \
        libpq-dev || error "Error installing packages"
    pip3 install passlib[bcrypt] || error "Error installing passlib"
    success "Prerequisites installed successfully"
}

setup_environment() {
    info "Setting up system environment..."
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER" || 
            error "Error creating user $SERVICE_USER"
    fi
    mkdir -p \
        "$INSTALL_DIR" \
        "$CONFIG_DIR" \
        "$LOG_DIR/panel" \
        "$XRAY_DIR" || error "Error creating directories"
    touch "$LOG_DIR/panel/access.log" "$LOG_DIR/panel/error.log"
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR" "$LOG_DIR"
    chmod -R 750 "$INSTALL_DIR" "$LOG_DIR"
    success "Environment setup completed"
}

setup_database() {
    info "Setting up PostgreSQL database..."
    sudo -u postgres psql <<EOF || error "Error executing PostgreSQL commands"
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    \c $DB_NAME
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF
    local pg_conf="/etc/postgresql/$(ls /etc/postgresql)/main/postgresql.conf"
    sed -i '/^#listen_addresses/s/^#//; s/localhost/*/' "$pg_conf"
    echo "host $DB_NAME $DB_USER 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
    systemctl restart postgresql || error "Error restarting PostgreSQL"
    success "Database setup completed"
}

clone_repository() {
    info "Cloning code repository..."
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR"
        git reset --hard || error "Error resetting changes"
        git pull || error "Error pulling updates"
    else
        git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || 
            error "Error cloning repository"
    fi
    find "$INSTALL_DIR" -type d -exec chmod 750 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 640 {} \;
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    success "Code repository cloned successfully"
}

setup_python() {
    info "Setting up Python environment..."
    python3 -m venv "$INSTALL_DIR/venv" || error "Error creating virtual environment"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install -U pip wheel || error "Error upgrading pip"
    pip install \
        fastapi==0.103.2 \
        uvicorn==0.23.2 \
        sqlalchemy==2.0.28 \
        psycopg2-binary==2.9.9 \
        python-dotenv==1.0.0 \
        pydantic-settings==2.0.3 \
        pydantic[email] \
        passlib[bcrypt]==1.7.4 \
        python-jose[cryptography]==3.3.0 || error "Error installing requirements"
    deactivate
    chown "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/venv/bin/uvicorn"
    chmod 750 "$INSTALL_DIR/venv/bin/uvicorn"
    success "Python environment setup completed"
}

create_admin_user() {
    info "Creating admin user in database..."
    cat > /tmp/create_admin.py <<EOF
import psycopg2
from passlib.context import CryptContext
import uuid
from datetime import datetime

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

conn = psycopg2.connect(
    dbname="$DB_NAME",
    user="$DB_USER",
    password="$DB_PASSWORD",
    host="localhost"
)
cur = conn.cursor()

hashed_password = pwd_context.hash("$ADMIN_PASS")
admin_uuid = str(uuid.uuid4())
now = datetime.now()

cur.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(120) UNIQUE NOT NULL,
        hashed_password VARCHAR(255) NOT NULL,
        uuid UUID UNIQUE NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP NOT NULL,
        updated_at TIMESTAMP NOT NULL
    )
""")

cur.execute("""
    INSERT INTO users (username, email, hashed_password, uuid, is_active, created_at, updated_at)
    VALUES (%s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (username) DO NOTHING
""", ("$ADMIN_USER", "admin@example.com", hashed_password, admin_uuid, True, now, now))

conn.commit()
cur.close()
conn.close()
EOF
    "$INSTALL_DIR/venv/bin/python" /tmp/create_admin.py || error "Error creating admin user"
    rm /tmp/create_admin.py
    success "Admin user created successfully"
}

install_xray() {
    info "Installing and configuring Xray..."
    systemctl stop xray 2>/dev/null || true
    if ! wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip; then
        error "Error downloading Xray"
    fi
    if ! unzip -o /tmp/xray.zip -d "$XRAY_DIR"; then
        error "Error extracting Xray"
    fi
    chmod +x "$XRAY_EXECUTABLE"
    if ! REALITY_KEYS=$("$XRAY_EXECUTABLE" x25519); then
        error "Error generating Reality keys"
    fi
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning",
        "access": "$LOG_DIR/xray-access.log",
        "error": "$LOG_DIR/xray-error.log"
    },
    "inbounds": [
        {
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "$XRAY_UUID", "flow": "xtls-rprx-vision"}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.datadoghq.com:443",
                    "xver": 0,
                    "serverNames": ["www.datadoghq.com"],
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "shortIds": ["$REALITY_SHORT_ID"],
                    "fingerprint": "chrome"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http","tls"]
            }
        },
        {
            "port": $XRAY_HTTP_PORT,
            "protocol": "vmess",
            "settings": {
                "clients": [{"id": "$XRAY_UUID"}]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$XRAY_PATH"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]
}
EOF
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now xray || error "Error starting Xray"
    success "Xray installed and configured successfully"
}

setup_nginx() {
    info "Setting up NGINX..."
    systemctl stop nginx 2>/dev/null || true
    read -p "Using a custom domain? (y/n) " use_domain
    if [[ "$use_domain" =~ ^[Yy]$ ]]; then
        read -p "Enter your domain name: " domain
        PANEL_DOMAIN="$domain"
    else
        PANEL_DOMAIN="$(curl -s ifconfig.me)"
    fi
    cat > /etc/nginx/conf.d/zhinapanel.conf <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    location $XRAY_PATH {
        proxy_pass http://127.0.0.1:$XRAY_HTTP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF
    systemctl start nginx || error "Error starting NGINX"
    success "NGINX configured successfully"
}

setup_ssl() {
    info "Setting up SSL certificate..."
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        mkdir -p /etc/nginx/ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/privkey.pem \
            -out /etc/nginx/ssl/fullchain.pem \
            -subj "/CN=$PANEL_DOMAIN"
        ssl_type="self-signed"
    else
        if certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}; then
            ssl_type="letsencrypt"
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
        else
            error "Error obtaining Let's Encrypt certificate"
        fi
    fi
    success "SSL setup completed (type: $ssl_type)"
}

setup_env_file() {
    info "Setting up .env file..."
    mkdir -p "$INSTALL_DIR/backend"
    cat > "$INSTALL_DIR/backend/.env" <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
SECRET_KEY=$(openssl rand -hex 32)
LOG_DIR=$LOG_DIR/panel
ACCESS_LOG=$LOG_DIR/panel/access.log
ERROR_LOG=$LOG_DIR/panel/error.log
LOG_LEVEL=info
XRAY_REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
XRAY_REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
EOF
    chown "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/backend/.env"
    chmod 600 "$INSTALL_DIR/backend/.env"
    success ".env file setup completed"
}

setup_panel_service() {
    info "Setting up panel service..."
    cat > /etc/systemd/system/zhinapanel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
Environment="PATH=$INSTALL_DIR/venv/bin"
Environment="PYTHONPATH=$INSTALL_DIR/backend"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn \
    app:app \
    --host 0.0.0.0 \
    --port $PANEL_PORT \
    --workers $UVICORN_WORKERS \
    --log-level info \
    --access-log \
    --no-server-header
Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/panel/access.log
StandardError=append:$LOG_DIR/panel/error.log

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now zhinapanel || error "Error starting panel service"
    sleep 3
    if ! systemctl is-active --quiet zhinapanel; then
        journalctl -u zhinapanel -n 50 --no-pager
        error "Panel service did not start. Please check the logs."
    fi
    success "Panel service setup completed"
}

show_installation_info() {
    echo -e "\n${GREEN}Installation completed successfully ===${NC}"
    echo -e "\n${YELLOW}Panel access details: ${NC}"
    echo -e "• Panel URL: ${GREEN}http://$PANEL_DOMAIN:$PANEL_PORT${NC}"
    echo -e "• Admin Username: ${YELLOW}$ADMIN_USER${NC}"
    echo -e "• Admin Password: ${YELLOW}$ADMIN_PASS${NC}"
    echo -e "\n${YELLOW}Xray settings: ${NC}"
    echo -e "• UUID: ${YELLOW}$XRAY_UUID${NC}"
    echo -e "• Public Key: ${YELLOW}$REALITY_PUBLIC_KEY${NC}"
    echo -e "• Short ID: ${YELLOW}$REALITY_SHORT_ID${NC}"
    echo -e "• WS Path: ${YELLOW}$XRAY_PATH${NC}"
    echo -e "\n${YELLOW}Service management commands: ${NC}"
    echo -e "• Check service status: ${GREEN}systemctl status xray nginx zhinapanel${NC}"
    echo -e "• View panel logs: ${GREEN}tail -f $LOG_DIR/panel/{access,error}.log${NC}"
    echo -e "• View Xray logs: ${GREEN}journalctl -u xray -f${NC}"
    cat > "$INSTALL_DIR/installation-info.txt" <<EOF
=== Zhina Panel Installation Details ===

Panel URL: http://$PANEL_DOMAIN:$PANEL_PORT
Admin Username: $ADMIN_USER
Admin Password: $ADMIN_PASS

Xray Settings:
- VLESS+Reality:
  • Port: 8443
  • UUID: $XRAY_UUID
  • Public Key: $REALITY_PUBLIC_KEY
  • Short ID: $REALITY_SHORT_ID
- VMESS+WS:
  • Port: $XRAY_HTTP_PORT
  • Path: $XRAY_PATH

Database Info:
- Username: $DB_USER
- Password: $DB_PASSWORD
- Database: $DB_NAME

Log Files:
- Panel Access: $LOG_DIR/panel/access.log
- Panel Errors: $LOG_DIR/panel/error.log
- Xray Logs: /var/log/zhinapanel/xray-{access,error}.log
EOF
    chmod 600 "$INSTALL_DIR/installation-info.txt"
}

main() {
    check_system
    install_prerequisites
    setup_environment
    setup_database
    clone_repository
    setup_python
    setup_env_file
    create_admin_user
    install_xray
    setup_nginx
    setup_ssl
    setup_panel_service
    show_installation_info
    echo -e "\n${GREEN}To view full installation details, check the log file: ${YELLOW}/var/log/zhinainstall.log${NC}"
}

main
