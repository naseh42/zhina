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

# ------------------- توابع پیشرفته -------------------
install_xray_with_all_protocols() {
    info "نصب Xray با تمام پروتکل‌ها..."
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
        // ===== VLESS + Reality ===== //
        {
            "port": 443,
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
                    "privateKey": "$REALITY_KEY"
                }
            }
        },
        // ===== VMess + WS ===== //
        {
            "port": 8080,
            "protocol": "vmess",
            "settings": {
                "clients": [{"id": "$XRAY_UUID"}]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {"path": "$XRAY_PATH"}
            }
        },
        // ===== Trojan ===== //
        {
            "port": 8443,
            "protocol": "trojan",
            "settings": {
                "clients": [{"password": "$XRAY_UUID"}]
            }
        },
        // ===== Shadowsocks ===== //
        {
            "port": 8388,
            "protocol": "shadowsocks",
            "settings": {
                "method": "aes-256-gcm",
                "password": "$XRAY_UUID"
            }
        },
        // ===== Hysteria ===== //
        {
            "port": 2095,
            "protocol": "hysteria",
            "settings": {
                "auth": "$XRAY_UUID",
                "obfs": "$XRAY_PATH"
            }
        },
        // ===== TUIC ===== //
        {
            "port": 2096,
            "protocol": "tuic",
            "settings": {
                "token": "$XRAY_UUID"
            }
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
}

setup_ssl_certificates() {
    info "تنظیم گواهی SSL..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/privkey.pem \
        -out /etc/nginx/ssl/fullchain.pem \
        -subj "/CN=$(curl -s ifconfig.me)"
}

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
}

create_systemd_services() {
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
}

# ------------------- بخش ساخت و اجرای requirements.txt -------------------
setup_requirements() {
    info "ایجاد و نصب فایل requirements.txt..."
    
    # ایجاد فایل requirements.txt با محتوای مورد نیاز
    cat > $INSTALL_DIR/requirements.txt <<EOF
fastapi>=0.95.0
uvicorn>=0.21.0
python-multipart>=0.0.6
psycopg2-binary>=2.9.5
python-jose>=3.3.0
passlib>=1.7.4
python-dotenv>=1.0.0
sqlalchemy>=2.0.0
alembic>=1.10.0
httpx>=0.24.0
cryptography>=40.0.0
pyotp>=2.8.0
apscheduler>=3.9.0
python-crontab>=2.6.0
EOF

    # نصب وابستگی‌ها
    sudo -u $SERVICE_USER $INSTALL_DIR/venv/bin/pip install -r $INSTALL_DIR/requirements.txt
    
    success "فایل requirements.txt با موفقیت ایجاد و وابستگی‌ها نصب شدند."
}

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

    echo -e "\nاطلاعات requirements.txt:"
    echo -e "• مسیر فایل: ${YELLOW}$INSTALL_DIR/requirements.txt${NC}"
    echo -e "• تعداد وابستگی‌های نصب شده: ${YELLOW}$(wc -l < $INSTALL_DIR/requirements.txt)${NC}"

    echo -e "\nدستورات مدیریت:"
    echo -e "• وضعیت Xray: ${YELLOW}systemctl status xray${NC}"
    echo -e "• وضعیت پنل: ${YELLOW}systemctl status zhina-panel${NC}"
    echo -e "• مشاهده لاگ‌ها: ${YELLOW}journalctl -u xray -u zhina-panel -f${NC}"
    echo -e "• بروزرسانی وابستگی‌ها: ${YELLOW}sudo -u $SERVICE_USER $INSTALL_DIR/venv/bin/pip install -r $INSTALL_DIR/requirements.txt --upgrade${NC}"
}

# ------------------- مراحل اصلی -------------------
main() {
    # 1. بررسی دسترسی root
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد!"

    # 2. نصب پیش‌نیازها
    info "نصب پیش‌نیازهای سیستم..."
    apt-get update
    apt-get install -y git python3 python3-venv python3-pip postgresql nginx curl wget openssl unzip uuid-runtime

    # 3. ایجاد کاربر سرویس
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d $INSTALL_DIR $SERVICE_USER
    fi

    # 4. تنظیمات دیتابیس
    info "تنظیم پایگاه داده..."
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$(openssl rand -hex 16)';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF

    # 5. کپی فایل‌های برنامه
    info "کپی فایل‌های برنامه..."
    git clone https://github.com/naseh42/zhina.git $INSTALL_DIR
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR

    # 6. محیط مجازی و وابستگی‌ها
    info "ایجاد محیط مجازی..."
    sudo -u $SERVICE_USER python3 -m venv $INSTALL_DIR/venv
    
    # 6.1 ساخت و نصب requirements.txt
    setup_requirements

    # 7. نصب و پیکربندی Xray
    install_xray_with_all_protocols

    # 8. تنظیمات SSL
    setup_ssl_certificates

    # 9. ایجاد جداول دیتابیس
    create_database_tables

    # 10. سرویس‌های سیستم
    create_systemd_services

    # 11. نمایش اطلاعات نهایی
    show_final_info
}

main
