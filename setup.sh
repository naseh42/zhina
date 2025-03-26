#!/bin/bash
set -euo pipefail

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina"
CONFIG_DIR="/etc/zhina"
LOG_DIR="/var/log/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
PANEL_PORT=8001
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -hex 8)
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
XRAY_HTTP_PORT=8080  # تغییر از 80 به 8080 برای جلوگیری از تداخل
DB_PASSWORD=$(openssl rand -hex 16)

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ------------------- اعمال اصلاحات ساختاری -------------------
apply_project_fixes() {
    info "اعمال اصلاحات ساختاری پروژه..."
    
    # ایجاد فایل requirements.txt در مسیر پروژه
    cat > "$INSTALL_DIR/requirements.txt" <<'EOF'
fastapi==0.103.2
uvicorn==0.23.2
sqlalchemy==2.0.28
psycopg2-binary==2.9.9
python-dotenv==1.0.0
pydantic-settings==2.0.3
python-multipart==0.0.6
jinja2==3.1.2
EOF

    # اصلاح فایل config.py
    cat > "$INSTALL_DIR/backend/config.py" <<'EOF'
from pydantic_settings import BaseSettings
from pydantic import Field
from typing import Optional

class Settings(BaseSettings):
    DATABASE_URL: str = Field(default="postgresql://zhina_user:password@localhost/zhina_db")
    XRAY_CONFIG_PATH: str = Field(default="/usr/local/bin/xray/config.json")
    XRAY_UUID: str = Field(...)
    XRAY_PATH: str = Field(default="/xray")
    REALITY_PUBLIC_KEY: str = Field(...)
    REALITY_SHORT_ID: str = Field(...)
    SECRET_KEY: str = Field(default=...)
    DEBUG: bool = Field(default=False)
    ADMIN_USERNAME: str = Field(default="admin")
    ADMIN_PASSWORD: str = Field(default="admin123")
    ADMIN_EMAIL: str = Field(default="admin@example.com")
    LANGUAGE: str = Field(default="fa")
    THEME: str = Field(default="dark")
    ENABLE_NOTIFICATIONS: bool = Field(default=True)

    class Config:
        env_file = "/etc/zhina/.env"
        env_file_encoding = 'utf-8'

settings = Settings()
EOF

    # بهبود فایل database.py
    cat > "$INSTALL_DIR/backend/database.py" <<'EOF'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from backend.config import settings

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600,
    pool_size=20,
    max_overflow=30
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF

    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    success "اصلاحات ساختاری اعمال شد!"
}

# ------------------- تنظیمات دامنه -------------------
configure_domain() {
    info "تنظیمات دامنه..."
    read -p "آیا می‌خواهید از دامنه اختصاصی استفاده کنید؟ (y/n) " USE_DOMAIN
    
    if [[ "$USE_DOMAIN" =~ ^[Yy]$ ]]; then
        read -p "لطفا نام دامنه خود را وارد کنید: " PANEL_DOMAIN
        PUBLIC_IP=$(curl -s ifconfig.me)
        echo -e "\nلطفا این رکورد DNS را تنظیم کنید:"
        echo -e "${YELLOW}$PANEL_DOMAIN A $PUBLIC_IP${NC}"
        read -p "پس از تنظیم DNS، Enter بزنید..."
    else
        PANEL_DOMAIN=$(curl -s ifconfig.me)
    fi
}

# ------------------- تنظیمات SSL -------------------
setup_ssl() {
    info "تنظیم گواهی SSL..."
    
    mkdir -p /etc/nginx/ssl
    
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/privkey.pem \
            -out /etc/nginx/ssl/fullchain.pem \
            -subj "/CN=${PANEL_DOMAIN}"
        SSL_TYPE="self-signed"
    else
        if ! command -v certbot &>/dev/null; then
            apt-get install -y certbot python3-certbot-nginx
        fi
        
        if certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}; then
            SSL_TYPE="letsencrypt"
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
        else
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/ssl/privkey.pem \
                -out /etc/nginx/ssl/fullchain.pem \
                -subj "/CN=${PANEL_DOMAIN}"
            SSL_TYPE="self-signed"
        fi
    fi
    
    chmod 600 /etc/nginx/ssl/*
    success "SSL تنظیم شد (نوع: ${SSL_TYPE})"
}

# ------------------- تنظیمات Nginx -------------------
configure_nginx() {
    info "تنظیم Nginx..."
    
    systemctl stop xray || true
    
    cat > /etc/nginx/conf.d/panel.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    
    location / {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}

server {
    listen 443 ssl;
    server_name ${PANEL_DOMAIN};
    
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location / {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location ${XRAY_PATH} {
        proxy_pass http://127.0.0.1:${XRAY_HTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    
    nginx -t || error "خطا در کانفیگ Nginx"
    systemctl restart nginx
    systemctl start xray
    success "Nginx تنظیم شد!"
}

# ------------------- نصب و تنظیم Xray -------------------
install_xray() {
    info "نصب و پیکربندی Xray..."
    
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"
    mkdir -p "$XRAY_DIR"
    
    if ! wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip; then
        error "خطا در دانلود Xray"
    fi
    unzip -o /tmp/xray.zip -d "$XRAY_DIR" || error "خطا در استخراج Xray"
    chmod +x "$XRAY_EXECUTABLE"

    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    
    REALITY_KEYS=$("$XRAY_EXECUTABLE" x25519)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    REALITY_DEST="www.datadoghq.com:443"
    REALITY_SERVER_NAMES='["www.datadoghq.com","www.lovelive.jp"]'

    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {"loglevel": "warning"},
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
                    "dest": "$REALITY_DEST",
                    "xver": 0,
                    "serverNames": $REALITY_SERVER_NAMES,
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
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "blocked"}
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
    systemctl enable --now xray
    success "Xray نصب و راه‌اندازی شد!"
}

# ------------------- توابع اصلی -------------------
install_prerequisites() {
    info "نصب پیش‌نیازها..."
    apt-get update
    apt-get install -y git python3 python3-venv python3-pip postgresql nginx curl wget openssl unzip uuid-runtime
    success "پیش‌نیازها نصب شدند!"
}

setup_database() {
    info "تنظیم دیتابیس..."
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF
    success "دیتابیس تنظیم شد!"
}

setup_virtualenv() {
    info "تنظیم محیط مجازی پایتون..."
    python3 -m venv "$INSTALL_DIR/venv" || error "خطا در ایجاد محیط مجازی"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install -U pip wheel
    pip install -r "$INSTALL_DIR/requirements.txt" || error "خطا در نصب نیازمندی‌ها"
    deactivate
    success "محیط مجازی تنظیم شد!"
}

create_tables() {
    info "ایجاد جداول دیتابیس..."
    sudo -u postgres psql -d $DB_NAME <<EOF
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(255) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    INSERT INTO users (username, password) 
    VALUES ('$ADMIN_USER', crypt('$ADMIN_PASS', gen_salt('bf')));
EOF
    success "جداول ایجاد شدند!"
}

setup_services() {
    info "تنظیم سرویس‌ها..."
    
    mkdir -p $CONFIG_DIR
    cat > "$CONFIG_DIR/.env" <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME
XRAY_UUID=$XRAY_UUID
XRAY_PATH=$XRAY_PATH
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
EOF

    chmod 600 "$CONFIG_DIR/.env"
    ln -sf "$CONFIG_DIR/.env" "$INSTALL_DIR/backend/.env"

    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now zhina-panel
    success "سرویس‌ها تنظیم شدند!"
}

show_info() {
    echo -e "\n${GREEN}=== نصب کامل شد! ===${NC}"
    echo -e "پنل مدیریت: ${YELLOW}http://${PANEL_DOMAIN}:${PANEL_PORT}${NC}"
    echo -e "یوزرنیم: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "رمز عبور: ${YELLOW}${ADMIN_PASS}${NC}"
    echo -e "\nتنظیمات Xray:"
    echo -e "UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    echo -e "Short ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
    echo -e "Path: ${YELLOW}${XRAY_PATH}${NC}"
    echo -e "\nدستورات مدیریت:"
    echo -e "وضعیت سرویس‌ها: ${YELLOW}systemctl status {xray,zhina-panel,nginx}${NC}"
    echo -e "مشاهده لاگ‌ها: ${YELLOW}journalctl -u xray -u zhina-panel -f${NC}"
}

main() {
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد!"
    
    install_prerequisites
    useradd -r -s /bin/false -d $INSTALL_DIR $SERVICE_USER || true
    setup_database
    
    info "دریافت کدهای برنامه..."
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        git pull || error "خطا در بروزرسانی"
    else
        git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || error "خطا در دریافت کدها"
    fi
    
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    apply_project_fixes
    setup_virtualenv
    configure_domain
    setup_ssl
    install_xray
    configure_nginx
    create_tables
    setup_services
    
    show_info
}

main
