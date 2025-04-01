#!/bin/bash
set -euo pipefail
exec > >(tee -a "/var/log/zhina-install.log") 2>&1

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/opt/zhina"
BACKEND_DIR="$INSTALL_DIR/backend"
FRONTEND_DIR="$INSTALL_DIR/frontend"
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
ADMIN_EMAIL=""
ADMIN_PASS=""
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
XRAY_HTTP_PORT=2083  # تغییر 1: پورت Xray از 8080 به 2083
DB_PASSWORD=$(openssl rand -hex 16)
XRAY_PATH="/$(openssl rand -hex 8)"
SECRETS_DIR="/etc/zhina/secrets"
DEFAULT_THEME="dark"
DEFAULT_LANGUAGE="fa"
PANEL_DOMAIN=""

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { 
    echo -e "${RED}[✗] $1${NC}" >&2
    echo -e "برای مشاهده خطاهای کامل، فایل لاگ را بررسی کنید: ${YELLOW}/var/log/zhina-install.log${NC}"
    exit 1
}
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }
warning() { echo -e "${YELLOW}[!] $1${NC}"; }

# ------------------- دریافت اطلاعات ادمین -------------------
get_admin_credentials() {
    while [[ -z "$ADMIN_EMAIL" ]]; do
        read -p "لطفا ایمیل ادمین را وارد کنید: " ADMIN_EMAIL
        if [[ -z "$ADMIN_EMAIL" ]]; then
            echo -e "${RED}ایمیل ادمین نمی‌تواند خالی باشد!${NC}"
        fi
    done

    while [[ -z "$ADMIN_PASS" ]]; do
        read -sp "لطفا رمز عبور ادمین را وارد کنید (حداقل 8 کاراکتر): " ADMIN_PASS
        echo
        if [[ ${#ADMIN_PASS} -lt 8 ]]; then
            echo -e "${RED}رمز عبور باید حداقل 8 کاراکتر باشد!${NC}"
            ADMIN_PASS=""
        fi
    done
}

# ------------------- بررسی سیستم -------------------
check_system() {
    info "بررسی پیش‌نیازهای سیستم..."
    
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد"
    
    if [[ ! -f /etc/os-release ]]; then
        error "سیستم عامل نامشخص"
    fi
    source /etc/os-release
    [[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && 
        warning "این اسکریپت فقط بر روی Ubuntu/Debian تست شده است"
    
    for cmd in curl wget git python3; do
        if ! command -v $cmd &> /dev/null; then
            error "دستور $cmd یافت نشد!"
        fi
    done
    
    success "بررسی سیستم کامل شد"
}

# ------------------- نصب پیش‌نیازها -------------------
install_prerequisites() {
    info "نصب بسته‌های ضروری..."
    
    apt-get update -y || error "خطا در بروزرسانی لیست پکیج‌ها"
    
    apt-get install -y \
        git python3 python3-venv python3-pip \
        postgresql postgresql-contrib nginx \
        curl wget openssl unzip uuid-runtime \
        certbot python3-certbot-nginx \
        build-essential python3-dev libpq-dev || error "خطا در نصب پکیج‌ها"
    
    success "پیش‌نیازها با موفقیت نصب شدند"
}

# ------------------- تنظیم کاربر و دایرکتوری‌ها -------------------
setup_environment() {
    info "تنظیم محیط سیستم..."
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER" || 
            error "خطا در ایجاد کاربر $SERVICE_USER"
    fi
    
    sudo mkdir -p \
        "$BACKEND_DIR" \
        "$FRONTEND_DIR" \
        "$CONFIG_DIR" \
        "$LOG_DIR/panel" \
        "$XRAY_DIR" \
        "$SECRETS_DIR" \
        "/etc/xray" || error "خطا در ایجاد دایرکتوری‌ها"
    
    sudo chown -R "$SERVICE_USER":"$SERVICE_USER" \
        "$INSTALL_DIR" \
        "$LOG_DIR" \
        "$SECRETS_DIR" \
        "$CONFIG_DIR"
    
    sudo touch "$LOG_DIR/panel/access.log" "$LOG_DIR/panel/error.log"
    sudo chown "$SERVICE_USER":"$SERVICE_USER" "$LOG_DIR/panel"/*.log
    
    if [ -d "./backend" ]; then
        sudo cp -r "./backend"/* "$BACKEND_DIR"/ || error "خطا در انتقال بک‌اند"
    else
        error "پوشه backend در مسیر جاری یافت نشد!"
    fi
    
    if [ -d "./frontend" ]; then
        sudo cp -r "./frontend"/* "$FRONTEND_DIR"/ || error "خطا در انتقال فرانت‌اند"
    else
        error "پوشه frontend در مسیر جاری یافت نشد!"
    fi
    
    sudo find "$BACKEND_DIR" -type d -exec chmod 750 {} \;
    sudo find "$BACKEND_DIR" -type f -exec chmod 640 {} \;
    sudo find "$FRONTEND_DIR" -type d -exec chmod 755 {} \;
    sudo find "$FRONTEND_DIR" -type f -exec chmod 644 {} \;
    
    success "محیط سیستم با موفقیت تنظیم شد"
}

# ------------------- تنظیم دیتابیس -------------------
setup_database() {
    info "تنظیم پایگاه داده PostgreSQL..."
    
    systemctl start postgresql || error "خطا در راه‌اندازی PostgreSQL"
    
    sudo -u postgres psql <<EOF || error "خطا در اجرای دستورات PostgreSQL"
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
    \c $DB_NAME
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF

    sudo -u postgres psql -c "
    ALTER USER $DB_USER WITH SUPERUSER;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
    " || error "خطا در اعطای دسترسی‌های بیشتر به کاربر دیتابیس"
    
    local pg_conf="/etc/postgresql/$(ls /etc/postgresql | head -1)/main/postgresql.conf"
    if [ -f "$pg_conf" ]; then
        sed -i '/^#listen_addresses/s/^#//; s/localhost/*/' "$pg_conf"
        echo "host $DB_NAME $DB_USER 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
    else
        warning "فایل پیکربندی PostgreSQL یافت نشد!"
    fi
    
    systemctl restart postgresql || error "خطا در راه‌اندازی مجدد PostgreSQL"
    
    sudo -u postgres psql -d "$DB_NAME" <<EOF
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE,
        hashed_password VARCHAR(255) NOT NULL,
        uuid UUID DEFAULT uuid_generate_v4(),
        traffic_limit BIGINT DEFAULT 0,
        usage_duration INTEGER DEFAULT 0,
        simultaneous_connections INTEGER DEFAULT 1,
        is_active BOOLEAN DEFAULT TRUE,
        is_admin BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS domains (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL,
        description TEXT,
        owner_id INTEGER REFERENCES users(id),
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS subscriptions (
        id SERIAL PRIMARY KEY,
        uuid UUID DEFAULT uuid_generate_v4(),
        data_limit BIGINT,
        expiry_date TIMESTAMP,
        max_connections INTEGER,
        user_id INTEGER REFERENCES users(id),
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS settings (
        id SERIAL PRIMARY KEY,
        language VARCHAR(10) DEFAULT '$DEFAULT_LANGUAGE',
        theme VARCHAR(20) DEFAULT '$DEFAULT_THEME',
        enable_notifications BOOLEAN DEFAULT TRUE,
        preferences JSONB,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS nodes (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        ip_address VARCHAR(45) NOT NULL,
        port INTEGER NOT NULL,
        protocol VARCHAR(20) NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS inbounds (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        settings JSONB NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS xray_configs (
        id SERIAL PRIMARY KEY,
        config_name VARCHAR(100) NOT NULL,
        protocol VARCHAR(20) NOT NULL,
        port INTEGER NOT NULL,
        settings JSONB NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS xray_users (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        username VARCHAR(100),
        email VARCHAR(100),
        password VARCHAR(100),
        limit_ip INTEGER,
        limit_device INTEGER,
        expire_date TIMESTAMP,
        data_limit BIGINT,
        enabled BOOLEAN DEFAULT TRUE,
        config_id INTEGER REFERENCES xray_configs(id),
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS user_traffic (
        id SERIAL PRIMARY KEY,
        user_id UUID REFERENCES xray_users(id),
        download BIGINT DEFAULT 0,
        upload BIGINT DEFAULT 0,
        total BIGINT GENERATED ALWAYS AS (download + upload) STORED,
        date DATE NOT NULL DEFAULT CURRENT_DATE,
        UNIQUE(user_id, date)
    );

    CREATE TABLE IF NOT EXISTS connection_logs (
        id SERIAL PRIMARY KEY,
        user_id UUID REFERENCES xray_users(id),
        ip VARCHAR(45) NOT NULL,
        user_agent TEXT,
        connected_at TIMESTAMP DEFAULT NOW(),
        disconnected_at TIMESTAMP,
        duration INTERVAL GENERATED ALWAYS AS (
            CASE WHEN disconnected_at IS NULL THEN NULL
            ELSE disconnected_at - connected_at END
        ) STORED
    );

    INSERT INTO users (username, email, hashed_password, uuid, traffic_limit, usage_duration, simultaneous_connections, is_active, is_admin, created_at, updated_at)
    VALUES ('$ADMIN_USER', '$ADMIN_EMAIL', crypt('$ADMIN_PASS', gen_salt('bf')), uuid_generate_v4(), 0, 0, 1, TRUE, TRUE, NOW(), NOW())
    ON CONFLICT (username) DO NOTHING;

    INSERT INTO settings (language, theme, enable_notifications)
    VALUES ('$DEFAULT_LANGUAGE', '$DEFAULT_THEME', TRUE)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO xray_configs (config_name, protocol, port, settings)
    VALUES ('default_vless', 'vless', 8443, '{"flow": "xtls-rprx-vision", "security": "reality"}'),
           ('default_vmess', 'vmess', $XRAY_HTTP_PORT, '{"network": "ws", "path": "$XRAY_PATH"}')
    ON CONFLICT (id) DO NOTHING;
EOF
    
    success "پایگاه داده و جداول با موفقیت ایجاد شدند"
}

# ------------------- تنظیم محیط پایتون -------------------
setup_python() {
    info "تنظیم محیط پایتون..."
    
    python3 -m venv "$INSTALL_DIR/venv" || error "خطا در ایجاد محیط مجازی"
    source "$INSTALL_DIR/venv/bin/activate"
    
    pip install --upgrade pip wheel || error "خطا در بروزرسانی pip و wheel"
    
    # تغییر 2: نصب نیازمندی‌های پایتون با نسخه‌های ثابت
    pip install \
        fastapi==0.95.0 \
        uvicorn==0.21.0 \
        psycopg2-binary==2.9.5 \
        sqlalchemy==2.0.0 \
        python-dotenv==1.0.0 \
        python-jose==3.3.0 \
        passlib==1.7.4 \
        email-validator==1.3.1 \
        "pydantic[email]"==1.10.7 \
        alembic==1.10.0 \
        aiofiles==23.1.0 \
        python-multipart==0.0.6 \
        anyio==3.6.2 \
        async-timeout==4.0.2 \
        cryptography==38.0.4 \
        || error "خطا در نصب نیازمندی‌های پایتون"
    
    deactivate
    
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/venv"
    chmod 750 "$INSTALL_DIR/venv/bin/uvicorn" 2>/dev/null || true
    
    success "محیط پایتون تنظیم شد"
}

# ------------------- نصب Xray -------------------
install_xray() {
    info "نصب و پیکربندی Xray..."
    
    systemctl stop xray 2>/dev/null || true
    
    if ! wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip; then
        error "خطا در دانلود Xray"
    fi
    
    if ! unzip -o /tmp/xray.zip -d "$XRAY_DIR"; then
        error "خطا در استخراج Xray"
    fi
    
    chmod +x "$XRAY_EXECUTABLE"

    if ! REALITY_KEYS=$("$XRAY_EXECUTABLE" x25519); then
        error "خطا در تولید کلیدهای Reality"
    fi
    
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    XRAY_UUID=$(uuidgen)

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
    systemctl enable --now xray || error "خطا در راه‌اندازی Xray"
    
    sleep 2
    if ! systemctl is-active --quiet xray; then
        journalctl -u xray -n 20 --no-pager
        error "سرویس Xray فعال نشد. لطفاً خطاهای بالا را بررسی کنید."
    fi
    
    success "Xray با موفقیت نصب و پیکربندی شد"
}

# ------------------- تنظیم Nginx -------------------
setup_nginx() {
    info "تنظیم Nginx..."
    
    systemctl stop nginx 2>/dev/null || true
    
    read -p "آیا از دامنه اختصاصی استفاده می‌کنید؟ (y/n) " use_domain
    if [[ "$use_domain" =~ ^[Yy]$ ]]; then
        while [[ -z "$PANEL_DOMAIN" ]]; do
            read -p "نام دامنه خود را وارد کنید (مثال: example.com): " PANEL_DOMAIN
            [[ -z "$PANEL_DOMAIN" ]] && echo -e "${RED}نام دامنه نمی‌تواند خالی باشد!${NC}"
        done
    else
        PANEL_DOMAIN="$(curl -s ifconfig.me)"
        echo -e "${YELLOW}از آدرس IP عمومی استفاده می‌شود: ${PANEL_DOMAIN}${NC}"
    fi

    cat > /etc/nginx/conf.d/zhina.conf <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    
    root $INSTALL_DIR/frontend;
    index index.html;
    
    location / {
        try_files \$uri /index.html;
    }
    
    location /api {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location /ws {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    
    location $XRAY_PATH {
        proxy_pass http://127.0.0.1:$XRAY_HTTP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    nginx -t || error "خطا در پیکربندی Nginx"
    systemctl restart nginx || error "خطا در راه‌اندازی Nginx"
    
    success "Nginx با موفقیت پیکربندی شد"
}

# ------------------- تنظیم SSL -------------------
setup_ssl() {
    info "تنظیم گواهی SSL..."
    
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        mkdir -p /etc/nginx/ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/privkey.pem \
            -out /etc/nginx/ssl/fullchain.pem \
            -subj "/CN=$PANEL_DOMAIN"
        ssl_type="self-signed"
        
        cat >> /etc/nginx/conf.d/zhina.conf <<EOF

server {
    listen 443 ssl;
    server_name $PANEL_DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location $XRAY_PATH {
        proxy_pass http://127.0.0.1:$XRAY_HTTP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    else
        if certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.} || \
           certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}; then
            ssl_type="letsencrypt"
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
        else
            warning "خطا در دریافت گواهی Let's Encrypt، از گواهی خودامضا استفاده می‌شود"
            setup_ssl
            return
        fi
    fi
    
    systemctl restart nginx || error "خطا در راه‌اندازی مجدد Nginx"
    
    success "SSL تنظیم شد (نوع: $ssl_type)"
}

# ------------------- تنظیم فایل محیط -------------------
setup_env() {
    info "تنظیم فایل محیط..."
    
    cat > "$BACKEND_DIR/.env" <<EOF
# تنظیمات دیتابیس
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME

# تنظیمات Xray
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
XRAY_UUID=$XRAY_UUID
XRAY_PATH=$XRAY_PATH
XRAY_HTTP_PORT=$XRAY_HTTP_PORT

# تنظیمات امنیتی
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
ADMIN_EMAIL=$ADMIN_EMAIL
SECRET_KEY=$(openssl rand -hex 32)

# تنظیمات پنل
PANEL_PORT=$PANEL_PORT
PANEL_DOMAIN=$PANEL_DOMAIN
DEFAULT_THEME=$DEFAULT_THEME
DEFAULT_LANGUAGE=$DEFAULT_LANGUAGE
EOF

    chmod 600 "$BACKEND_DIR/.env"
    chown "$SERVICE_USER":"$SERVICE_USER" "$BACKEND_DIR/.env"
    
    success "فایل .env در $BACKEND_DIR/.env ایجاد شد"
}

# ------------------- تنظیم سرویس پنل -------------------
setup_panel_service() {
    info "تنظیم سرویس پنل..."
    
    APP_FILE="$BACKEND_DIR/app.py"
    if [[ ! -f "$APP_FILE" ]]; then
        warning "فایل app.py در مسیر $BACKEND_DIR یافت نشد! یک فایل نمونه ایجاد می‌کنیم..."
        cat > "$APP_FILE" <<EOF
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "خوش آمدید به پنل مدیریت Zhina"}
EOF
    fi
    
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
Environment="PYTHONPATH=$BACKEND_DIR"
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
    systemctl enable --now zhina-panel || error "خطا در راه‌اندازی سرویس پنل"
    
    sleep 3
    if ! systemctl is-active --quiet zhina-panel; then
        journalctl -u zhina-panel -n 30 --no-pager
        error "سرویس پنل فعال نشد. لطفاً خطاهای بالا را بررسی کنید."
    fi
    
    success "سرویس پنل تنظیم شد"
}

# ------------------- نمایش اطلاعات نصب -------------------
show_installation_info() {
    local panel_url="https://${PANEL_DOMAIN}"
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        panel_url="http://${PANEL_DOMAIN}:${PANEL_PORT}"
    fi
    
    echo -e "\n${GREEN}=== نصب با موفقیت کامل شد ===${NC}"
    echo -e "\n${YELLOW}مشخصات دسترسی:${NC}"
    echo -e "• پنل مدیریت: ${GREEN}${panel_url}${NC}"
    echo -e "• کاربر ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "• ایمیل ادمین: ${YELLOW}${ADMIN_EMAIL}${NC}"
    echo -e "• رمز عبور: ${YELLOW}${ADMIN_PASS}${NC}"
    
    echo -e "\n${YELLOW}تنظیمات Xray:${NC}"
    echo -e "• UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    echo -e "• Short ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
    echo -e "• مسیر WS: ${YELLOW}${XRAY_PATH}${NC}"
    
    echo -e "\n${YELLOW}اطلاعات دیتابیس:${NC}"
    echo -e "• نام دیتابیس: ${YELLOW}${DB_NAME}${NC}"
    echo -e "• کاربر دیتابیس: ${YELLOW}${DB_USER}${NC}"
    echo -e "• رمز عبور دیتابیس: ${YELLOW}${DB_PASSWORD}${NC}"
    
    echo -e "\n${YELLOW}دستورات مدیریت:${NC}"
    echo -e "• وضعیت سرویس‌ها: ${GREEN}systemctl status xray nginx zhina-panel postgresql${NC}"
    echo -e "• مشاهده لاگ پنل: ${GREEN}tail -f $LOG_DIR/panel/{access,error}.log${NC}"
    echo -e "• مشاهده لاگ Xray: ${GREEN}journalctl -u xray -f${NC}"
    
    cat > "$INSTALL_DIR/installation-info.txt" <<EOF
=== Zhina Panel Installation Details ===

Panel URL: ${panel_url}
Admin Username: ${ADMIN_USER}
Admin Email: ${ADMIN_EMAIL}
Admin Password: ${ADMIN_PASS}

Database Info:
- Database: ${DB_NAME}
- Username: ${DB_USER}
- Password: ${DB_PASSWORD}

Xray Settings:
- VLESS+Reality:
  • Port: 8443
  • UUID: ${XRAY_UUID}
  • Public Key: ${REALITY_PUBLIC_KEY}
  • Short ID: ${REALITY_SHORT_ID}
- VMESS+WS:
  • Port: ${XRAY_HTTP_PORT}
  • Path: ${XRAY_PATH}

Log Files:
- Panel Access: ${LOG_DIR}/panel/access.log
- Panel Errors: ${LOG_DIR}/panel/error.log
- Xray Logs: /var/log/zhina/xray-{access,error}.log
EOF

    chmod 600 "$INSTALL_DIR/installation-info.txt"
}

# ------------------- تابع اصلی -------------------
main() {
    clear
    echo -e "${GREEN}"
    echo "   ____  _     _           "
    echo "  |__ / (_) __| | ___  _ _ "
    echo "   |_ \ | |/ _\` |/ _ \| '_|"
    echo "  |___/ |_|\__,_|\___/|_|  "
    echo -e "${NC}"
    
    check_system
    get_admin_credentials
    install_prerequisites
    setup_environment
    setup_database
    setup_python
    install_xray
    setup_nginx
    setup_ssl
    setup_env
    setup_panel_service
    show_installation_info
    
    echo -e "\n${GREEN}برای مشاهده جزئیات کامل، فایل لاگ را بررسی کنید:${NC}"
    echo -e "${YELLOW}tail -f /var/log/zhina-install.log${NC}"
}

main
