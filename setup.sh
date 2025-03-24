#!/bin/bash
set -euo pipefail

# ----- Configuration -----
INSTALL_DIR="/var/lib/zhina"
TEMP_DIR="/tmp/zhina_temp"
XRAY_DIR="/usr/local/bin/xray"
DB_NAME="zhina_db"
DB_USER="zhina_user"
XRAY_PORT=443
PANEL_PORT=8000
DOMAIN="${1:-$(curl -s ifconfig.me)}"  # Use IP if no domain provided

# ----- Colors & Messages -----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ----- Cleanup Function -----
cleanup() {
    rm -rf "$TEMP_DIR"
    systemctl stop xray 2>/dev/null || true
}

# ----- Main Installation -----
main() {
    # 1. Check root access
    [[ $EUID -ne 0 ]] && error "Run with root privileges!"

    # 2. Clean previous installs
    info "Cleaning previous installations..."
    cleanup
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # 3. Install dependencies
    info "Installing dependencies..."
    apt-get update
    apt-get install -y \
        git python3 python3-venv python3-pip \
        postgresql postgresql-contrib \
        nginx curl wget openssl unzip

    # 4. Database Setup
    info "Configuring database..."
    local DB_PASS=$(openssl rand -hex 16)
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP ROLE IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
    CREATE DATABASE $DB_NAME;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
    echo "host all all 127.0.0.1/32 md5" >> /etc/postgresql/*/main/pg_hba.conf
    systemctl restart postgresql

    # 5. Xray Installation
    info "Installing Xray..."
    XRAY_VER="1.8.11"
    mkdir -p "$XRAY_DIR"
    wget -qO /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VER/Xray-linux-64.zip"
    unzip -o /tmp/xray.zip -d "$XRAY_DIR"
    chmod +x "$XRAY_DIR/xray"

    # 6. Xray Configuration
    XRAY_UUID=$(uuidgen)
    cat > "$XRAY_DIR/config.json" <<EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "port": $XRAY_PORT,
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "$XRAY_UUID"}],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "security": "tls",
            "tlsSettings": {
                "certificates": [{
                    "certificateFile": "/etc/nginx/ssl/cert.pem",
                    "keyFile": "/etc/nginx/ssl/key.pem"
                }]
            }
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

    # 7. SSL Certificate
    info "Generating SSL certificate..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/key.pem \
        -out /etc/nginx/ssl/cert.pem \
        -subj "/CN=$DOMAIN"

    # 8. Nginx Configuration
    info "Configuring Nginx..."
    cat > /etc/nginx/sites-available/zhina <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/zhina /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx

    # 9. Panel Installation
    info "Installing control panel..."
    git clone https://github.com/naseh42/zhina.git "$TEMP_DIR"
    cp -r "$TEMP_DIR"/* "$INSTALL_DIR"
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install -r "$INSTALL_DIR/requirements.txt"

    # 10. Final Configuration
    cat > "$INSTALL_DIR/.env" <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME
XRAY_UUID=$XRAY_UUID
PANEL_PORT=$PANEL_PORT
EOF

    # 11. Start Services
    systemctl enable xray
    systemctl start xray

    success "Installation completed!"
    echo -e "\n======================="
    echo "Panel URL: https://$DOMAIN"
    echo "UUID: $XRAY_UUID"
    echo "DB Password: $DB_PASS"
    echo "======================="
}

# ----- Run Installation -----
main
