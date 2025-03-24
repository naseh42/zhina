#!/bin/bash
set -euo pipefail

# ----- تنظیمات اصلی -----
INSTALL_DIR="/var/lib/zhina"
TEMP_DIR="/tmp/zhina_temp"
REPO_URL="https://github.com/naseh42/zhina.git"
DB_NAME="zhina_db"
DB_USER="zhina_user"
XRAY_PORT=443
PANEL_PORT=8000

# ----- رنگ‌ها و توابع -----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ----- بررسی دسترسی root -----
if [[ $EUID -ne 0 ]]; then
    error "این اسکریپت نیاز به دسترسی root دارد!"
fi

# ----- حذف و ایجاد دایرکتوری‌ها -----
rm -rf "$INSTALL_DIR" "$TEMP_DIR"
mkdir -p "$INSTALL_DIR" "$TEMP_DIR"

# ----- نصب پیش‌نیازها -----
info "نصب پیش‌نیازهای مورد نیاز..."
apt-get update
apt-get install -y --no-install-recommends git python3 python3-venv python3-pip postgresql curl unzip openssl nginx
success "پیش‌نیازها با موفقیت نصب شدند."
# ----- تنظیم پایگاه داده -----
setup_database() {
    info "راه‌اندازی پایگاه داده PostgreSQL..."
    local DB_PASS=$(openssl rand -hex 16)
    
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP ROLE IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
    CREATE DATABASE $DB_NAME;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

    echo "host all all 127.0.0.1/32 md5" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
    systemctl restart postgresql || error "خطا در راه‌اندازی مجدد PostgreSQL!"

    # ذخیره اطلاعات پایگاه داده در فایل .env
    cat > "$INSTALL_DIR/.env" <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME
SECRET_KEY=$(openssl rand -hex 32)
EOF
    success "پایگاه داده با موفقیت تنظیم شد."
    create_tables() {
    info "ایجاد جداول پایگاه داده بر اساس مدل‌ها..."

    source "$INSTALL_DIR/venv/bin/activate"
    python3 -c "
from sqlalchemy import create_engine
from backend.database import Base
from models import User, Domain, Subscription, Setting, Node
import os
from dotenv import load_dotenv

load_dotenv(os.path.join('$INSTALL_DIR', '.env'))
DATABASE_URL = os.getenv('DATABASE_URL')
engine = create_engine(DATABASE_URL)
Base.metadata.create_all(engine)
" || error "خطا در ایجاد جداول پایگاه داده!"

    deactivate
    success "جداول با موفقیت ایجاد شدند!"
}
}
install_panel() {
    info "نصب پنل کنترلی..."
    git clone "$REPO_URL" "$TEMP_DIR" || error "خطا در کلون کردن مخزن Git!"
    cp -r "$TEMP_DIR"/* "$INSTALL_DIR"/ || error "خطا در کپی فایل‌ها به دایرکتوری نصب."
    
    # اگر requirements.txt موجود نبود، آن را بساز
    if [[ ! -f "$INSTALL_DIR/requirements.txt" ]]; then
        cat > "$INSTALL_DIR/requirements.txt" <<EOF
sqlalchemy==2.0.28
psycopg2-binary==2.9.9
fastapi==0.103.2
uvicorn==0.23.2
python-multipart==0.0.6
jinja2==3.1.2
python-dotenv==1.0.0
EOF
    fi
    
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install -r "$INSTALL_DIR/requirements.txt" || error "خطا در نصب وابستگی‌ها!"
    deactivate
    success "پنل با موفقیت نصب شد!"
}
# ----- تنظیم و نصب Xray -----
configure_xray() {
    info "در حال پیکربندی Xray..."

    # دانلود آخرین نسخه Xray
    curl -sL https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o $TEMP_DIR/xray.zip || error "خطا در دانلود Xray"
    unzip $TEMP_DIR/xray.zip -d /usr/local/bin/xray || error "خطا در استخراج فایل‌های Xray"
    chmod +x /usr/local/bin/xray/xray || error "خطا در تنظیم مجوزهای Xray"

    # ایجاد فایل تنظیمات Xray
    cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$(uuidgen)",
            "level": 0,
            "email": "vless@example.com"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": false
        }
      }
    },
    {
      "port": 80,
      "protocol": "http",
      "settings": {}
    },
    {
      "port": 443,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$(openssl rand -hex 16)",
            "email": "trojan@example.com"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
    info "فایل تنظیمات Xray با موفقیت ایجاد شد."

    # راه‌اندازی سرویس Xray
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray/xray -config /etc/xray/config.json
Restart=always
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray || error "خطا در فعال‌سازی Xray"
    systemctl restart xray || error "خطا در راه‌اندازی Xray"
    success "Xray با موفقیت نصب و تنظیم شد!"
}
setup_ssl() {
    info "در حال تنظیم گواهی SSL..."

    # دریافت دامنه از کاربر
    read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN

    if [[ -n "$DOMAIN" ]]; then
        info "گواهی معتبر برای دامنه $DOMAIN دریافت می‌شود..."
        apt-get install -y certbot || error "خطا در نصب Certbot!"
        certbot certonly --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || error "خطا در دریافت گواهی SSL!"
        SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    else
        info "گواهی Self-Signed برای آی‌پی تنظیم می‌شود..."
        mkdir -p /etc/nginx/ssl || error "خطا در ایجاد دایرکتوری SSL!"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt -subj "/CN=$(curl -s ifconfig.me)" || error "خطا در ایجاد گواهی Self-Signed!"
        SSL_CERT="/etc/nginx/ssl/nginx.crt"
        SSL_KEY="/etc/nginx/ssl/nginx.key"
    fi

    success "گواهی SSL با موفقیت تنظیم شد."
}
setup_uvicorn() {
    info "پیکربندی و اجرای Uvicorn..."

    # ایجاد فایل systemd برای Uvicorn
    cat > /etc/systemd/system/uvicorn.service <<EOF
[Unit]
Description=Uvicorn Service
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable uvicorn || error "خطا در فعال‌سازی سرویس Uvicorn!"
    systemctl restart uvicorn || error "خطا در راه‌اندازی سرویس Uvicorn!"
    success "Uvicorn با موفقیت اجرا شد!"
}
display_info() {
    success "نصب و تنظیم به پایان رسید!"
    echo -e "\n====== اطلاعات دسترسی ======"
    echo "• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}:${PANEL_PORT}"
    echo "• یوزرنیم ادمین: admin"
    echo "• پسورد ادمین: (در فایل .env ذخیره شده)"
    echo "• پورت Xray: $XRAY_PORT"
    echo "• وضعیت Uvicorn: فعال"
    echo -e "================================="
}
