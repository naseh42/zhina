#!/bin/bash
set -euo pipefail

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina"
XRAY_DIR="/usr/local/bin/xray"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
PANEL_PORT=8000
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -hex 8)
XRAY_VERSION="1.8.11"  # نسخه Xray
UVICORN_WORKERS=4

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ------------------- نصب پیش‌نیازها -------------------
echo "Installing system prerequisites..."
install_prerequisites() {
    info "نصب پیش‌نیازهای سیستم..."
    apt-get update
    apt-get install -y git python3 python3-venv python3-pip postgresql nginx curl wget openssl unzip
    success "پیش‌نیازها با موفقیت نصب شدند!"
}
# ------------------- تنظیم پایگاه داده -------------------
echo "Starting database setup..."
setup_database() {
    info "تنظیم پایگاه داده..."
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$(openssl rand -hex 16)';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF
    success "پایگاه داده با موفقیت تنظیم شد!"
}
# ------------------- ساخت و اجرای فایل requirements.txt -------------------
echo "Creating and installing requirements..."
setup_requirements() {
    info "ایجاد فایل requirements.txt..."
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
        success "فایل requirements.txt ایجاد شد!"
    else
        info "فایل requirements.txt از قبل موجود است."
    fi

    info "نصب وابستگی‌های مورد نیاز..."
    python3 -m venv $INSTALL_DIR/venv
    source $INSTALL_DIR/venv/bin/activate
    pip install -U pip setuptools wheel
    pip install -r "$INSTALL_DIR/requirements.txt" || error "خطا در نصب وابستگی‌ها!"
    deactivate
    success "وابستگی‌ها با موفقیت نصب شدند!"
}
# ------------------- نصب و تنظیم Xray -------------------
echo "Installing and configuring Xray..."
install_xray_with_all_protocols() {
    info "نصب Xray با تمام پروتکل‌ها..."
    
    # دانلود آخرین نسخه Xray
    wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d "$XRAY_DIR"
    chmod +x "$XRAY_DIR/xray"

    # تولید UUID و مسیر تصادفی
    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    REALITY_KEY=$(openssl rand -hex 32)

    # فایل کانفیگ پیشرفته
    cat > "$XRAY_DIR/config.json" <<EOF
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

    success "Xray با تمام پروتکل‌ها با موفقیت نصب و تنظیم شد!"
}
# ------------------- تنظیم گواهی SSL -------------------
echo "Setting up SSL certificates..."
setup_ssl_certificates() {
    info "تنظیم گواهی SSL..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/privkey.pem \
        -out /etc/nginx/ssl/fullchain.pem \
        -subj "/CN=$(curl -s ifconfig.me)"
    success "گواهی SSL با موفقیت ایجاد شد!"
}
# ------------------- ایجاد جداول دیتابیس -------------------
echo "Creating database tables..."
create_database_tables() {
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

    -- ایجاد کاربر ادمین
    INSERT INTO users (username, password, is_active) 
    VALUES ('$ADMIN_USER', crypt('$ADMIN_PASS', gen_salt('bf')), true);
EOF
    success "جداول دیتابیس با موفقیت ایجاد شدند!"
}
# ------------------- سرویس‌های systemd -------------------
echo "Creating and starting systemd services..."
create_systemd_services() {
    info "ایجاد سرویس‌های systemd..."

    # سرویس Xray
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=$XRAY_DIR/xray run -config $XRAY_DIR/config.json
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # سرویس پنل مدیریتی
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
    success "سرویس‌های systemd با موفقیت ایجاد و راه‌اندازی شدند!"
}
# ------------------- نمایش اطلاعات نهایی -------------------
echo "Showing final setup information..."
show_final_info() {
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
