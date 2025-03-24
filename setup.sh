#!/bin/bash
set -euo pipefail

# ----- تنظیمات اصلی -----
INSTALL_DIR="/var/lib/zhina"
TEMP_DIR="/tmp/zhina_temp"
XRAY_DIR="/usr/local/bin/xray"
DB_NAME="zhina_db"
DB_USER="zhina_user"
DOMAIN="your-domain.com"  # جایگزین کنید
XRAY_PORT=443
PANEL_PORT=8000

# ----- رنگ‌ها و توابع پیام -----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ----- توابع کمکی -----
cleanup() {
    info "پاکسازی محیط..."
    rm -rf "$TEMP_DIR"
    rm -rf "$INSTALL_DIR/venv"
}

check_root() {
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد!"
}

# ----- نصب پیش‌نیازها -----
install_dependencies() {
    info "نصب پیش‌نیازهای سیستم..."
    apt-get update
    apt-get install -y \
        git python3 python3-venv python3-pip \
        postgresql postgresql-contrib \
        nginx curl wget openssl unzip
}

# ----- تنظیمات دیتابیس -----
setup_database() {
    info "تنظیم پایگاه داده PostgreSQL..."
    local DB_PASS=$(openssl rand -hex 16)

    # حذف نسخه‌های قبلی
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
    sudo -u postgres psql -c "DROP ROLE IF EXISTS $DB_USER;" 2>/dev/null || true

    # ایجاد کاربر و دیتابیس جدید
    sudo -u postgres psql <<EOF
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
    CREATE DATABASE $DB_NAME;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

    # تنظیمات احراز هویت
    sed -i '/host all all 127.0.0.1\/32 md5/d' /etc/postgresql/*/main/pg_hba.conf
    echo "host all all 127.0.0.1/32 md5" >> /etc/postgresql/*/main/pg_hba.conf
    systemctl restart postgresql

    # ذخیره اطلاعات در فایل env
    cat > "$INSTALL_DIR/.env" <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME
XRAY_UUID=$(uuidgen)
XRAY_PANEL_PORT=$PANEL_PORT
EOF
}

# ----- نصب و پیکربندی Xray -----
install_xray() {
    info "نصب Xray Core..."
    local XRAY_VER="1.8.11"
    
    mkdir -p "$XRAY_DIR"
    wget -qO "$TEMP_DIR/xray.zip" "https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VER/Xray-linux-64.zip"
    unzip -o "$TEMP_DIR/xray.zip" -d "$XRAY_DIR"
    chmod +x "$XRAY_DIR/xray"

    # ایجاد فایل کانفیگ
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

    # ایجاد سرویس سیستم
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=$XRAY_DIR/xray run -config $XRAY_DIR/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray
}

# ----- تنظیمات SSL -----
setup_ssl() {
    info "تولید گواهی SSL..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/key.pem \
        -out /etc/nginx/ssl/cert.pem \
        -subj "/CN=$DOMAIN"
}

# ----- پیکربندی Nginx -----
setup_nginx() {
    info "پیکربندی Nginx..."
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
}

# ----- نصب پنل -----
install_panel() {
    info "نصب پنل مدیریتی..."
    git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR"
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install -r "$INSTALL_DIR/requirements.txt"

    # اجرای مهاجرت‌های دیتابیس
    python3 "$INSTALL_DIR/manage.py" migrate
}

# ----- نمایش اطلاعات نهایی -----
show_info() {
    success "نصب کامل شد!"
    echo -e "\n=== اطلاعات دسترسی ==="
    echo "آدرس پنل: https://$DOMAIN"
    echo "UUID Xray: $(grep XRAY_UUID "$INSTALL_DIR/.env" | cut -d= -f2)"
    echo "پورت پنل: $PANEL_PORT"
    echo "مسیر نصب: $INSTALL_DIR"
}

# ----- اجرای اصلی -----
main() {
    check_root
    cleanup
    install_dependencies
    setup_database
    setup_ssl
    install_xray
    setup_nginx
    install_panel
    show_info
}

main
