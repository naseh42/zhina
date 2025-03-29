#!/bin/bash
set -euo pipefail
exec > >(tee -a "/var/log/zhina-install.log") 2>&1

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina/backend"
CONFIG_DIR="/etc/zhina"
LOG_DIR="/var/log/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
XRAY_CONFIG="/etc/xray/config.json"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
PANEL_PORT=8001
ADMIN_USER="admin"
ADMIN_EMAIL="admin@example.com"
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
XRAY_HTTP_PORT=8080
DB_PASSWORD=$(openssl rand -hex 16)
XRAY_PATH="/$(openssl rand -hex 8)"
SECRETS_DIR="/etc/zhina/secrets"
DEFAULT_THEME="dark"
DEFAULT_LANGUAGE="fa"

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { 
    echo -e "${RED}[✗] $1${NC}" >&2
    exit 1
}
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }

# ------------------- بررسی root -------------------
check_root() {
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد"
    success "بررسی دسترسی root موفقیت‌آمیز بود"
}

# ------------------- دریافت اطلاعات ادمین -------------------
get_admin_credentials() {
    read -p "لطفا ایمیل ادمین را وارد کنید: " ADMIN_EMAIL
    while true; do
        read -sp "لطفا رمز عبور ادمین را وارد کنید (حداقل 8 کاراکتر): " ADMIN_PASS
        echo
        [[ ${#ADMIN_PASS} -ge 8 ]] && break
        echo -e "${RED}رمز عبور باید حداقل 8 کاراکتر باشد!${NC}"
    done
}

# ------------------- نصب پیش‌نیازها -------------------
install_prerequisites() {
    info "نصب بسته‌های ضروری..."
    apt-get update -y
    apt-get install -y \
        git python3 python3-venv python3-pip \
        postgresql postgresql-contrib nginx \
        curl wget openssl unzip uuid-runtime \
        jq build-essential
    success "پیش‌نیازها نصب شدند"
}

# ------------------- تنظیم دیتابیس -------------------
setup_database() {
    info "تنظیم پایگاه داده PostgreSQL..."
    
    sudo -u postgres psql <<EOF || error "خطا در اجرای دستورات PostgreSQL"
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
    \c $DB_NAME
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOF

    sudo -u postgres psql -d "$DB_NAME" <<EOF || error "خطا در ایجاد جداول"
    CREATE TABLE users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE,
        hashed_password VARCHAR(255) NOT NULL,
        uuid VARCHAR(36) UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
        traffic_limit BIGINT DEFAULT 0,
        usage_duration INTEGER DEFAULT 30,
        simultaneous_connections INTEGER DEFAULT 3,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE domains (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL,
        description JSONB,
        owner_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE subscriptions (
        id SERIAL PRIMARY KEY,
        uuid VARCHAR(36) UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
        data_limit BIGINT,
        expiry_date TIMESTAMP NOT NULL,
        max_connections INTEGER DEFAULT 3,
        user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE settings (
        id SERIAL PRIMARY KEY,
        language VARCHAR(2) DEFAULT 'fa' CHECK (language IN ('fa', 'en')),
        theme VARCHAR(10) DEFAULT 'dark' CHECK (theme IN ('dark', 'light', 'auto')),
        enable_notifications BOOLEAN DEFAULT TRUE,
        preferences JSONB DEFAULT '{}',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    INSERT INTO users (username, email, hashed_password, is_active)
    VALUES (
        '$ADMIN_USER',
        '$ADMIN_EMAIL',
        crypt('$ADMIN_PASS', gen_salt('bf')),
        TRUE
    );

    INSERT INTO settings (language, theme)
    VALUES ('$DEFAULT_LANGUAGE', '$DEFAULT_THEME');
EOF

    success "پایگاه داده و جداول ایجاد شدند"
}

# ------------------- نصب Xray-core -------------------
install_xray() {
    info "در حال نصب Xray-core..."
    
    # حذف نسخه‌های قبلی
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR" "$XRAY_CONFIG"
    
    # دریافت آخرین نسخه
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.tag_name' | sed 's/v//')
    TEMP_DIR=$(mktemp -d)
    
    # دانلود و استخراج
    wget "https://github.com/XTLS/Xray-core/releases/download/v${LATEST_VERSION}/Xray-linux-64.zip" -O "$TEMP_DIR/xray.zip" || error "خطا در دانلود Xray"
    unzip "$TEMP_DIR/xray.zip" -d "$TEMP_DIR" || error "خطا در استخراج فایل‌ها"
    
    # نصب فایل‌ها
    install -m 755 "$TEMP_DIR/xray" "$XRAY_DIR/xray"
    mkdir -p /usr/share/xray
    cp "$TEMP_DIR/geoip.dat" "$TEMP_DIR/geosite.dat" "/usr/share/xray/"
    
    # تولید کلیدها
    XRAY_KEYS=$("$XRAY_DIR/xray" x25519)
    PRIVATE_KEY=$(jq -r '.privateKey' <<< "$XRAY_KEYS")
    PUBLIC_KEY=$(jq -r '.publicKey' <<< "$XRAY_KEYS")
    XRAY_UUID=$(uuidgen)
    
    # پیکربندی Xray
    mkdir -p /etc/xray
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning",
        "access": "$LOG_DIR/xray-access.log",
        "error": "$LOG_DIR/xray-error.log"
    },
    "inbounds": [
        {
            "port": 443,
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
                    "privateKey": "$PRIVATE_KEY",
                    "shortIds": ["$(openssl rand -hex 4)"],
                    "fingerprint": "chrome"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        }
    ]
}
EOF

    # سرویس Systemd
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$XRAY_DIR/xray run -config $XRAY_CONFIG
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray
    success "Xray-core v$LATEST_VERSION نصب شد"
}

# ------------------- نصب پنل -------------------
install_panel() {
    info "در حال نصب پنل مدیریت..."
    
    # دریافت کدها
    git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || error "خطا در دریافت کدها"
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    
    # محیط مجازی
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install -r "$INSTALL_DIR/requirements.txt"
    deactivate
    
    # فایل محیطی
    cat > "$INSTALL_DIR/.env" <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME
XRAY_UUID=$XRAY_UUID
XRAY_PUBLIC_KEY=$PUBLIC_KEY
SECRET_KEY=$(openssl rand -hex 32)
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
PANEL_DOMAIN=localhost
EOF

    # سرویس Systemd
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn backend.app:app --host 0.0.0.0 --port $PANEL_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now zhina-panel
    success "پنل مدیریت نصب شد"
}

# ------------------- نمایش اطلاعات -------------------
show_info() {
    echo -e "\n${GREEN}=== نصب موفقیت‌آمیز ===${NC}"
    echo -e "دسترسی پنل مدیریت: ${YELLOW}http://$(curl -s ifconfig.me):$PANEL_PORT${NC}"
    echo -e "مشخصات ادمین:"
    echo -e " - ایمیل: ${YELLOW}$ADMIN_EMAIL${NC}"
    echo -e " - رمز عبور: ${YELLOW}(رمز وارد شده)${NC}"
    echo -e "\nمشخصات Xray:"
    echo -e " - UUID: ${YELLOW}$XRAY_UUID${NC}"
    echo -e " - Public Key: ${YELLOW}$PUBLIC_KEY${NC}"
    echo -e "\nلاگ‌ها: ${YELLOW}/var/log/zhina/*.log${NC}"
}

# ------------------- تابع اصلی -------------------
main() {
    check_root
    get_admin_credentials
    install_prerequisites
    setup_database
    install_xray
    install_panel
    show_info
}

main
