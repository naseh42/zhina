#!/bin/bash
set -euo pipefail

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina"
CONFIG_DIR="/etc/zhina"
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
    
    # اصلاح فایل config.py
    cat > "$INSTALL_DIR/backend/config.py" <<'EOF'
from pydantic_settings import BaseSettings
from pathlib import Path

class Settings(BaseSettings):
    database_url: str = "postgresql://zhina_user:1fed62488ca9d549ca440eeb9cb4e6de@localhost/zhina_db"
    xray_config_path: str = "/etc/xray/config.json"
    admin_username: str = "admin"
    admin_password: str = "ade5140fb315cfa3"
    
    class Config:
        env_file = "/etc/zhina/.env"
        env_file_encoding = 'utf-8'
        extra = 'ignore'

settings = Settings()
EOF

    # اصلاح فایل database.py
    cat > "$INSTALL_DIR/backend/database.py" <<'EOF'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from backend.config import settings

SQLALCHEMY_DATABASE_URL = settings.database_url

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_size=20,
    max_overflow=30,
    pool_pre_ping=True
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

    # تنظیم مجوزها
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    success "اصلاحات ساختاری با موفقیت اعمال شدند!"
}

# ------------------- تنظیمات دامنه -------------------
configure_domain() {
    info "تنظیمات دامنه..."
    read -p "آیا می‌خواهید از دامنه اختصاصی استفاده کنید؟ (y/n) " USE_DOMAIN
    
    if [[ "$USE_DOMAIN" =~ ^[Yy]$ ]]; then
        read -p "لطفا نام دامنه خود را وارد کنید (مثال: panel.example.com): " PANEL_DOMAIN
        PUBLIC_IP=$(curl -s ifconfig.me)
        echo -e "\nلطفا رکورد DNS زیر را در پنل مدیریت دامنه خود تنظیم کنید:"
        echo -e "${YELLOW}${PANEL_DOMAIN} A ${PUBLIC_IP}${NC}"
        echo -e "پس از تنظیم DNS، 5 دقیقه صبر کنید و سپس Enter بزنید"
        read -p "آیا DNS را تنظیم کرده‌اید؟ (Enter) "
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
        apt-get install -y certbot python3-certbot-nginx
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
    success "گواهی SSL با موفقیت تنظیم شد (نوع: ${SSL_TYPE})"
}

# ------------------- تنظیمات Nginx -------------------
configure_nginx() {
    info "تنظیم Nginx..."
    
    systemctl stop xray || true
    
    rm -f /etc/nginx/sites-enabled/*
    
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
    ssl_prefer_server_ciphers on;
    
    location / {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    
    if ! nginx -t; then
        error "خطا در کانفیگ Nginx"
    fi
    
    systemctl restart nginx
    systemctl start xray
    success "Nginx با موفقیت تنظیم شد!"
}

# ------------------- نصب و تنظیم Xray -------------------
install_xray() {
    info "نصب و پیکربندی Xray..."
    
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"
    
    mkdir -p "$XRAY_DIR"
    wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d "$XRAY_DIR"
    chmod +x "$XRAY_EXECUTABLE"

    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    
    REALITY_KEYS=$($XRAY_EXECUTABLE x25519)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)

    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [
        {
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "$XRAY_UUID"}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.amazon.com:443",
                    "xver": 0,
                    "serverNames": ["www.amazon.com", "${PANEL_DOMAIN}"],
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "shortIds": ["$REALITY_SHORT_ID"]
                }
            }
        },
        {
            "port": 8080,
            "protocol": "vmess",
            "settings": {
                "clients": [{"id": "$XRAY_UUID"}]
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "path": "$XRAY_PATH",
                    "headers": {}
                }
            }
        },
        {
            "port": 8444,
            "protocol": "trojan",
            "settings": {
                "clients": [{"password": "$XRAY_UUID"}]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h2", "http/1.1"],
                    "certificates": [{
                        "certificateFile": "/etc/nginx/ssl/fullchain.pem",
                        "keyFile": "/etc/nginx/ssl/privkey.pem"
                    }]
                }
            }
        },
        {
            "port": 8388,
            "protocol": "shadowsocks",
            "settings": {
                "method": "aes-256-gcm",
                "password": "$XRAY_UUID",
                "network": "tcp,udp"
            }
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$XRAY_DIR
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray
    success "Xray با موفقیت نصب و پیکربندی شد!"
}

# ------------------- توابع باقی مانده -------------------
install_prerequisites() {
    info "نصب پیش‌نیازهای سیستم..."
    apt-get update
    apt-get install -y git python3 python3-venv python3-pip postgresql nginx curl wget openssl unzip uuid-runtime
    success "پیش‌نیازها با موفقیت نصب شدند!"
}

setup_database() {
    info "تنظیم پایگاه داده..."
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF
    sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    success "پایگاه داده با موفقیت تنظیم شد!"
}

setup_requirements() {
    info "ایجاد فایل requirements.txt..."
    cat > "$INSTALL_DIR/requirements.txt" <<EOF
sqlalchemy==2.0.28
psycopg2-binary==2.9.9
fastapi==0.103.2
uvicorn==0.23.2
python-multipart==0.0.6
jinja2==3.1.2
python-dotenv==1.0.0
pydantic-settings==2.0.3
EOF
    success "فایل requirements.txt ایجاد شد!"

    info "نصب وابستگی‌های مورد نیاز..."
    python3 -m venv $INSTALL_DIR/venv
    source $INSTALL_DIR/venv/bin/activate
    pip install -U pip setuptools wheel
    pip install -r "$INSTALL_DIR/requirements.txt"
    deactivate
    success "وابستگی‌ها با موفقیت نصب شدند!"
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
        traffic_limit BIGINT DEFAULT 0,
        usage_duration INT DEFAULT 0,
        simultaneous_connections INT DEFAULT 1,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS domains (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL,
        description JSONB,
        owner_id INT REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS subscriptions (
        id SERIAL PRIMARY KEY,
        uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
        data_limit BIGINT DEFAULT 0,
        expiry_date TIMESTAMP,
        max_connections INT DEFAULT 1,
        user_id INT REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS settings (
        id SERIAL PRIMARY KEY,
        language VARCHAR(10) DEFAULT 'fa',
        theme VARCHAR(20) DEFAULT 'dark',
        enable_notifications BOOLEAN DEFAULT true,
        preferences JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS nodes (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL,
        ip_address VARCHAR(45) NOT NULL,
        port INT NOT NULL,
        protocol VARCHAR(20) NOT NULL,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    INSERT INTO users (username, password, is_active) 
    VALUES ('$ADMIN_USER', crypt('$ADMIN_PASS', gen_salt('bf')), true);
EOF
    success "جداول دیتابیس با موفقیت ایجاد شدند!"
}

setup_services() {
    info "تنظیم سرویس‌های سیستم..."

    # ایجاد دایرکتوری کانفیگ
    mkdir -p $CONFIG_DIR

    # ایجاد فایل محیطی
    cat > "$CONFIG_DIR/.env" <<EOF
# تنظیمات دیتابیس
database_url=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME

# تنظیمات امنیتی
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False

# تنظیمات Xray
XRAY_UUID=$XRAY_UUID
XRAY_PATH=$XRAY_PATH
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID

# تنظیمات مدیریتی
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
EOF

    # لینک نمادین به فایل .env در دایرکتوری پروژه
    ln -sf "$CONFIG_DIR/.env" "$INSTALL_DIR/backend/.env"

    chown -R $SERVICE_USER:$SERVICE_USER $CONFIG_DIR
    chmod 600 "$CONFIG_DIR/.env"

    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
Environment="PATH=$INSTALL_DIR/venv/bin"
Environment="PYTHONPATH=$INSTALL_DIR:$INSTALL_DIR/backend"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT --workers $UVICORN_WORKERS
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zhina-panel
    systemctl start zhina-panel
    success "سرویس‌ها با موفقیت تنظیم و راه‌اندازی شدند!"
}

show_info() {
    PUBLIC_IP=$(curl -s ifconfig.me)
    success "\n\n=== نصب کامل شد! ==="
    
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "دسترسی پنل مدیریتی:"
        echo -e "• آدرس: ${YELLOW}http://${PANEL_DOMAIN}:${PANEL_PORT}${NC}"
    else
        echo -e "دسترسی پنل مدیریتی:"
        echo -e "• آدرس: ${GREEN}https://${PANEL_DOMAIN}${NC}"
    fi
    
    echo -e "• یوزرنیم ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "• پسورد ادمین: ${YELLOW}${ADMIN_PASS}${NC}"

    echo -e "\nتنظیمات Xray:"
    echo -e "• پروتکل‌های فعال:"
    echo -e "  - ${YELLOW}VLESS + Reality${NC} (پورت 8443)"
    echo -e "  - ${YELLOW}VMess + WS${NC} (پورت 8080 - مسیر: ${XRAY_PATH})"
    echo -e "  - ${YELLOW}Trojan${NC} (پورت 8444)"
    echo -e "  - ${YELLOW}Shadowsocks${NC} (پورت 8388)"
    echo -e "• UUID/پسورد مشترک: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• کلید عمومی Reality: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"

    echo -e "\nدستورات مدیریت:"
    echo -e "• وضعیت سرویس‌ها: ${YELLOW}systemctl status {xray,zhina-panel,nginx}${NC}"
    echo -e "• مشاهده لاگ‌ها: ${YELLOW}journalctl -u xray -u zhina-panel -f${NC}"
}

# ------------------- اجرای اصلی -------------------
main() {
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد!"

    install_prerequisites

    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d $INSTALL_DIR $SERVICE_USER
    fi

    setup_database

    info "دریافت کدهای برنامه..."
    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR"
        git pull || error "خطا در بروزرسانی کدها"
    else
        rm -rf "$INSTALL_DIR"
        git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || error "خطا در دریافت کدها"
    fi
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    success "کدهای برنامه با موفقیت دریافت شدند!"

    apply_project_fixes
    setup_requirements
    configure_domain
    setup_ssl
    configure_nginx
    install_xray
    create_tables
    setup_services
    show_info
}

main
