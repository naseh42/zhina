#!/bin/bash
set -euo pipefail

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray-core"  # تغییر نام فایل اجرایی برای جلوگیری از تداخل
XRAY_CONFIG="$XRAY_DIR/config.json"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
PANEL_PORT=8000
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -hex 8)
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ------------------- توابع اصلی -------------------
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
    CREATE USER $DB_USER WITH PASSWORD '$(openssl rand -hex 16)';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF
    # نصب extension مورد نیاز برای تابع gen_salt
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

install_xray() {
    info "نصب و پیکربندی Xray..."
    
    # حذف نسخه قبلی اگر وجود دارد
    sudo systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"
    
    # ایجاد دایرکتوری و دانلود Xray
    mkdir -p "$XRAY_DIR"
    wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d "$XRAY_DIR"
    
    # تغییر نام فایل اجرایی برای جلوگیری از تداخل
    mv "$XRAY_DIR/xray" "$XRAY_EXECUTABLE"
    chmod +x "$XRAY_EXECUTABLE"

    # تولید مقادیر تصادفی
    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    REALITY_KEY=$(openssl rand -hex 32)

    # ایجاد فایل کانفیگ
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {"clients": [{"id": "$XRAY_UUID"}], "decryption": "none"},
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.amazon.com:443",
                    "xver": 0,
                    "privateKey": "$REALITY_KEY"
                }
            }
        },
        {
            "port": 8080,
            "protocol": "vmess",
            "settings": {"clients": [{"id": "$XRAY_UUID"}]},
            "streamSettings": {
                "network": "ws",
                "wsSettings": {"path": "$XRAY_PATH"}
            }
        },
        {
            "port": 8443,
            "protocol": "trojan",
            "settings": {"clients": [{"password": "$XRAY_UUID"}]}
        },
        {
            "port": 8388,
            "protocol": "shadowsocks",
            "settings": {"method": "aes-256-gcm", "password": "$XRAY_UUID"}
        },
        {
            "port": 2095,
            "protocol": "hysteria",
            "settings": {"auth": "$XRAY_UUID", "obfs": "$XRAY_PATH"}
        },
        {
            "port": 2096,
            "protocol": "tuic",
            "settings": {"token": "$XRAY_UUID"}
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
    success "Xray با موفقیت نصب و پیکربندی شد!"
}

setup_ssl() {
    info "تنظیم گواهی SSL..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/privkey.pem \
        -out /etc/nginx/ssl/fullchain.pem \
        -subj "/CN=$(curl -s ifconfig.me)"
    success "گواهی SSL با موفقیت ایجاد شد!"
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

    # حذف تنظیمات قبلی اگر وجود دارد
    rm -f /etc/systemd/system/xray.service
    rm -rf /etc/systemd/system/xray.service.d

    # سرویس Xray
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(dirname "$XRAY_EXECUTABLE")
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=65535
Environment="XRAY_LOCATION_ASSET=$(dirname "$XRAY_EXECUTABLE")"

[Install]
WantedBy=multi-user.target
EOF

    # سرویس پنل
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT --workers $UVICORN_WORKERS
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray zhina-panel
    systemctl start xray zhina-panel
    success "سرویس‌ها با موفقیت تنظیم و راه‌اندازی شدند!"
}

show_info() {
    success "\n\n=== نصب کامل شد! ==="
    echo -e "دسترسی پنل مدیریتی:"
    echo -e "• آدرس: http://$(curl -s ifconfig.me):$PANEL_PORT"
    echo -e "• یوزرنیم ادمین: ${YELLOW}$ADMIN_USER${NC}"
    echo -e "• پسورد ادمین: ${YELLOW}$ADMIN_PASS${NC}"

    echo -e "\nتنظیمات Xray:"
    echo -e "• پروتکل‌های فعال:"
    echo -e "  - ${YELLOW}VLESS + Reality${NC} (پورت 443)"
    echo -e "  - ${YELLOW}VMess + WS${NC} (پورت 8080)"
    echo -e "  - ${YELLOW}Trojan${NC} (پورت 8443)"
    echo -e "  - ${YELLOW}Shadowsocks${NC} (پورت 8388)"
    echo -e "  - ${YELLOW}Hysteria${NC} (پورت 2095)"
    echo -e "  - ${YELLOW}TUIC${NC} (پورت 2096)"
    echo -e "• UUID/پسورد مشترک: ${YELLOW}$XRAY_UUID${NC}"
    echo -e "• مسیر WS: ${YELLOW}$XRAY_PATH${NC}"

    echo -e "\nدستورات مدیریت:"
    echo -e "• وضعیت Xray: ${YELLOW}systemctl status xray${NC}"
    echo -e "• وضعیت پنل: ${YELLOW}systemctl status zhina-panel${NC}"
    echo -e "• مشاهده لاگ‌ها: ${YELLOW}journalctl -u xray -u zhina-panel -f${NC}"
}

# ------------------- اجرای اصلی -------------------
main() {
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد!"

    # 1. نصب پیش‌نیازها
    install_prerequisites

    # 2. ایجاد کاربر سرویس
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d $INSTALL_DIR $SERVICE_USER
    fi

    # 3. تنظیم دیتابیس
    setup_database

    # 4. دریافت کدهای برنامه
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

    # 5. نصب وابستگی‌ها
    setup_requirements

    # 6. نصب Xray
    install_xray

    # 7. تنظیم SSL
    setup_ssl

    # 8. ایجاد جداول
    create_tables

    # 9. تنظیم سرویس‌ها
    setup_services

    # 10. نمایش اطلاعات
    show_info
}

main
