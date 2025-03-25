#!/bin/bash
# ===============================================
# نام اسکریپت: نصب کامل Zhina Panel + Xray-core
# نسخه: 4.2.1
# تاریخ آخرین بروزرسانی: 2025-03-26
# ===============================================

# ----------------------------
# بخش 1: تنظیمات اصلی و توابع
# ----------------------------
set -euo pipefail
exec 2> >(tee -a "/var/log/zhina-install.log")

# تنظیمات سیستمی
INSTALL_DIR="/var/lib/zhina"
CONFIG_DIR="/etc/zhina"
LOG_DIR="/var/log/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
DB_PASSWORD=$(openssl rand -hex 24)
PANEL_PORT=8001
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -hex 12)
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
XRAY_UUID=$(uuidgen)
XRAY_PATH="/$(openssl rand -hex 8)"
REALITY_SHORT_ID=$(openssl rand -hex 4)
XRAY_PORT=8443  # Changed from 443 to avoid conflict with Nginx
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# رنگ‌های کنسول
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# توابع کمکی
error() { echo -e "${RED}[✗] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }
warning() { echo -e "${YELLOW}[!] $1${NC}"; }

# ----------------------------
# بخش 2: اعتبارسنجی سیستم
# ----------------------------
validate_system() {
    info "بررسی پیش‌نیازهای سیستم..."
    
    # بررسی نسخه سیستم عامل
    if [[ ! -f /etc/os-release ]]; then
        error "سیستم عامل نامشخص"
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        warning "این اسکریپت فقط بر روی Ubuntu/Debian تست شده است"
    fi
    
    # بررسی دسترسی root
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد"
    
    # بررسی حافظه
    local mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    (( mem < 1000000 )) && warning "حداقل 1GB RAM توصیه می‌شود"
    
    # بررسی فضای دیسک
    local disk=$(df -h / | awk 'NR==2 {print $4}')
    [[ "${disk//[^0-9]/}" -lt 10 ]] && warning "حداقل 10GB فضای دیسک توصیه می‌شود"
    
    success "بررسی سیستم کامل شد"
}

# ----------------------------
# بخش 3: نصب پیش‌نیازها
# ----------------------------
install_prerequisites() {
    info "نصب پیش‌نیازهای سیستم..."
    
    apt-get update
    apt-get install -y \
        git python3 python3-venv python3-pip python3-dev \
        postgresql postgresql-contrib nginx \
        curl wget openssl unzip uuid-runtime jq \
        build-essential libssl-dev libffi-dev \
        certbot python3-certbot-nginx \
        fail2ban ufw
    
    # فعال کردن فایروال
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow $XRAY_PORT
    ufw --force enable
    
    # تنظیمات اولیه fail2ban
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    systemctl restart fail2ban
    
    success "پیش‌نیازها با موفقیت نصب شدند"
}

# ----------------------------
# بخش 4: تنظیم کاربر و دایرکتوری‌ها
# ----------------------------
setup_directories() {
    info "تنظیم دایرکتوری‌ها و کاربر سیستم..."
    
    # ایجاد کاربر سرویس
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"
    fi
    
    # ایجاد دایرکتوری‌های مورد نیاز
    mkdir -p \
        "$INSTALL_DIR" \
        "$CONFIG_DIR" \
        "$LOG_DIR" \
        "$XRAY_DIR" \
        "$INSTALL_DIR/backend" \
        "$INSTALL_DIR/frontend/static" \
        "$INSTALL_DIR/frontend/templates"
    
    # تنظیم مجوزها
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    chmod 750 "$INSTALL_DIR"
    
    success "دایرکتوری‌ها و کاربر سیستم تنظیم شدند"
}

# ----------------------------
# بخش 5: تنظیم دیتابیس PostgreSQL
# ----------------------------
setup_database() {
    info "تنظیم پایگاه داده PostgreSQL..."
    
    # ایجاد کاربر و دیتابیس
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    \c $DB_NAME
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF
    
    # تنظیمات امنیتی PostgreSQL
    local pg_conf="/etc/postgresql/$(ls /etc/postgresql)/main/postgresql.conf"
    sed -i '/^#listen_addresses/s/^#//; s/localhost/*/' "$pg_conf"
    echo "host $DB_NAME $DB_USER 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
    
    systemctl restart postgresql
    
    success "پایگاه داده PostgreSQL تنظیم شد"
}

# ----------------------------
# بخش 6: دریافت کدهای برنامه
# ----------------------------
clone_repository() {
    info "دریافت کدهای برنامه..."
    
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR"
        git reset --hard
        git pull || error "خطا در بروزرسانی کدها"
    else
        git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || error "خطا در دریافت کدها"
    fi
    
    # تنظیم مجوزهای فایل‌ها
    find "$INSTALL_DIR" -type d -exec chmod 750 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 640 {} \;
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    
    success "کدهای برنامه دریافت شدند"
}

# ----------------------------
# بخش 7: تنظیم محیط مجازی Python
# ----------------------------
setup_virtualenv() {
    info "تنظیم محیط مجازی Python..."
    
    # ایجاد محیط مجازی
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    
    # نصب وابستگی‌ها
    pip install --upgrade pip wheel setuptools
    pip install -r "$INSTALL_DIR/requirements.txt"
    
    deactivate
    
    success "محیط مجازی Python تنظیم شد"
}

# ----------------------------
# بخش 8: نصب و پیکربندی Xray-core
# ----------------------------
setup_xray() {
    info "نصب و پیکربندی Xray..."
    
    # توقف سرویس قبلی
    systemctl stop xray 2>/dev/null || true
    
    # حذف نسخه‌های قبلی
    rm -rf "$XRAY_DIR"/*
    mkdir -p "$XRAY_DIR"
    
    # دانلود و استخراج Xray
    if ! wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip; then
        error "خطا در دانلود Xray"
    fi
    
    if ! unzip -o /tmp/xray.zip -d "$XRAY_DIR"; then
        error "خطا در استخراج Xray"
    fi
    
    chmod +x "$XRAY_EXECUTABLE"

    # تولید کلیدهای Reality
    if ! REALITY_KEYS=$("$XRAY_EXECUTABLE" x25519); then
        error "خطا در تولید کلیدهای Reality"
    fi
    
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)

    # ایجاد کانفیگ Xray
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning",
        "access": "$LOG_DIR/xray-access.log",
        "error": "$LOG_DIR/xray-error.log"
    },
    "inbounds": [
        {
            "port": $XRAY_PORT,
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
                    "serverNames": ["www.amazon.com"],
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "shortIds": ["$REALITY_SHORT_ID"]
                }
            }
        },
        {
            "port": 80,
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
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "blocked"
            }
        ]
    }
}
EOF

    # ایجاد سرویس systemd برای Xray
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://xtls.github.io
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    
    # راه‌اندازی سرویس Xray
    systemctl daemon-reload
    systemctl enable --now xray
    
    # بررسی وضعیت سرویس
    if ! systemctl is-active --quiet xray; then
        journalctl -u xray -n 50 --no-pager
        error "سرویس Xray راه‌اندازی نشد"
    fi
    
    success "Xray با موفقیت نصب و پیکربندی شد"
}

# ----------------------------
# بخش 9: تنظیمات Nginx
# ----------------------------
setup_nginx() {
    info "تنظیم Nginx..."
    
    # توقف سرویس Nginx
    systemctl stop nginx 2>/dev/null || true
    
    # حذف کانفیگ‌های قبلی
    rm -f /etc/nginx/sites-enabled/*
    rm -f /etc/nginx/conf.d/*
    
    # ایجاد کانفیگ Nginx
    cat > /etc/nginx/conf.d/zhina.conf <<EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location $XRAY_PATH {
        proxy_pass http://127.0.0.1:80;
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
    
    # ایجاد دایرکتوری مورد نیاز
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    
    # راه‌اندازی مجدد Nginx
    systemctl start nginx
    
    # بررسی وضعیت Nginx
    if ! systemctl is-active --quiet nginx; then
        journalctl -u nginx -n 50 --no-pager
        error "سرویس Nginx راه‌اندازی نشد"
    fi
    
    success "Nginx با موفقیت پیکربندی شد"
}

# ----------------------------
# بخش 10: تنظیمات SSL
# ----------------------------
setup_ssl() {
    info "تنظیم گواهی SSL..."
    
    # نصب certbot در صورت عدم وجود
    if ! command -v certbot &>/dev/null; then
        apt-get install -y certbot python3-certbot-nginx
    fi
    
    # بررسی وجود دامنه
    read -p "آیا دامنه ثبت شده دارید؟ (y/n) " has_domain
    if [[ "$has_domain" =~ ^[Yy]$ ]]; then
        read -p "نام دامنه خود را وارد کنید: " domain_name
        
        # درخواست گواهی SSL برای دامنه
        if certbot --nginx --non-interactive --agree-tos --email admin@$domain_name -d $domain_name; then
            # تنظیم ربات تمدید خودکار
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
            success "گواهی SSL از Let's Encrypt دریافت شد"
        else
            warning "دریافت گواهی SSL از Let's Encrypt ناموفق بود، استفاده از خودامضا"
            create_self_signed_cert
        fi
    else
        warning "استفاده از گواهی خودامضا برای IP سرور"
        create_self_signed_cert
    fi
    
    # به‌روزرسانی کانفیگ Nginx برای SSL
    cat > /etc/nginx/conf.d/zhina-ssl.conf <<EOF
server {
    listen 443 ssl http2;
    server_name _;
    
    ssl_certificate $ssl_cert_path;
    ssl_certificate_key $ssl_key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location $XRAY_PATH {
        proxy_pass http://127.0.0.1:80;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    
    # راه‌اندازی مجدد Nginx
    systemctl restart nginx
    
    success "تنظیمات SSL کامل شد"
}

create_self_signed_cert() {
    # ایجاد گواهی خودامضا
    mkdir -p /etc/nginx/ssl
    ssl_cert_path="/etc/nginx/ssl/fullchain.pem"
    ssl_key_path="/etc/nginx/ssl/privkey.pem"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout $ssl_key_path \
        -out $ssl_cert_path \
        -subj "/CN=$(curl -s ifconfig.me)"
}

# ----------------------------
# بخش 11: ایجاد جداول دیتابیس
# ----------------------------
create_database_tables() {
    info "ایجاد جداول دیتابیس..."
    
    sudo -u postgres psql -d "$DB_NAME" <<EOF
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
        description TEXT,
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
    
    success "جداول دیتابیس ایجاد شدند"
}

# ----------------------------
# بخش 12: تنظیم فایل محیطی
# ----------------------------
setup_environment() {
    info "تنظیم فایل محیطی..."
    
    cat > "$CONFIG_DIR/.env" <<EOF
# تنظیمات دیتابیس
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME

# تنظیمات Xray
XRAY_UUID=$XRAY_UUID
XRAY_PATH=$XRAY_PATH
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
XRAY_CONFIG_PATH=$XRAY_CONFIG
XRAY_PORT=$XRAY_PORT

# تنظیمات امنیتی
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False
ACCESS_TOKEN_EXPIRE_MINUTES=30
JWT_ALGORITHM=HS256

# تنظیمات مدیریتی
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
ADMIN_EMAIL=admin@example.com

# تنظیمات اضافی
LANGUAGE=fa
THEME=dark
ENABLE_NOTIFICATIONS=True
EOF
    
    # تنظیم مجوزهای امنیتی
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$CONFIG_DIR"
    chmod 600 "$CONFIG_DIR/.env"
    
    # ایجاد لینک نمادین
    ln -sf "$CONFIG_DIR/.env" "$INSTALL_DIR/backend/.env"
    
    success "فایل محیطی تنظیم شد"
}

# ----------------------------
# بخش 13: تنظیم سرویس پنل
# ----------------------------
setup_panel_service() {
    info "تنظیم سرویس پنل مدیریتی..."
    
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
Environment="PATH=$INSTALL_DIR/venv/bin"
Environment="PYTHONPATH=$INSTALL_DIR"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT --workers $UVICORN_WORKERS --loop uvloop --http httptools
Restart=always
RestartSec=5s
StartLimitInterval=60s
StartLimitBurst=3

# تنظیمات امنیتی
ProtectSystem=full
PrivateTmp=true
NoNewPrivileges=true
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable --now zhina-panel
    
    # بررسی وضعیت سرویس
    sleep 5
    if ! systemctl is-active --quiet zhina-panel; then
        journalctl -u zhina-panel -n 50 --no-pager
        error "سرویس پنل مدیریتی راه‌اندازی نشد"
    fi
    
    success "سرویس پنل مدیریتی تنظیم شد"
}

# ----------------------------
# بخش 14: نمایش اطلاعات نصب
# ----------------------------
show_installation_info() {
    local public_ip=$(curl -s ifconfig.me)
    local panel_url="http://${public_ip}:${PANEL_PORT}"
    
    if [[ -f "/etc/letsencrypt/live/$(hostname)/fullchain.pem" ]]; then
        panel_url="https://$(hostname)"
    elif [[ -f "/etc/nginx/ssl/fullchain.pem" ]]; then
        panel_url="https://${public_ip}"
    fi
    
    echo -e "\n${GREEN}=== نصب با موفقیت کامل شد ===${NC}\n"
    echo -e "${BLUE}دسترسی به پنل مدیریتی:${NC}"
    echo -e "  • ${YELLOW}${panel_url}${NC}"
    echo -e "\n${BLUE}مشخصات ادمین:${NC}"
    echo -e "  • یوزرنیم: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "  • رمز عبور: ${YELLOW}${ADMIN_PASS}${NC}"
    echo -e "\n${BLUE}تنظیمات Xray:${NC}"
    echo -e "  • پروتکل VLESS+Reality (پورت ${XRAY_PORT})"
    echo -e "    - UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "    - Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    echo -e "    - Short ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
    echo -e "  • پروتکل VMESS+WS (پورت 80)"
    echo -e "    - UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "    - مسیر: ${YELLOW}${XRAY_PATH}${NC}"
    echo -e "\n${BLUE}دستورات مدیریتی:${NC}"
    echo -e "  • وضعیت سرویس‌ها: ${YELLOW}systemctl status zhina-panel xray nginx postgresql${NC}"
    echo -e "  • مشاهده لاگ‌ها: ${YELLOW}journalctl -u zhina-panel -f${NC}"
    echo -e "  • راه‌اندازی مجدد پنل: ${YELLOW}systemctl restart zhina-panel${NC}"
    echo -e "\n${RED}نکته امنیتی:${NC} حتماً رمز عبور ادمین و UUIDها را تغییر دهید!"
    
    # ذخیره اطلاعات در فایل
    cat > "$INSTALL_DIR/installation-info.txt" <<EOF
=== Zhina Panel Installation Details ===

Panel URL: $panel_url
Admin Username: $ADMIN_USER
Admin Password: $ADMIN_PASS

Xray Settings:
- VLESS+Reality (Port $XRAY_PORT)
  • UUID: $XRAY_UUID
  • Public Key: $REALITY_PUBLIC_KEY
  • Short ID: $REALITY_SHORT_ID
- VMESS+WS (Port 80)
  • UUID: $XRAY_UUID
  • Path: $XRAY_PATH

Database Info:
- Database Name: $DB_NAME
- Database User: $DB_USER
- Database Password: $DB_PASSWORD

Installation Directory: $INSTALL_DIR
Config Directory: $CONFIG_DIR
Log Directory: $LOG_DIR

=== End of Installation Details ===
EOF
    
    chmod 600 "$INSTALL_DIR/installation-info.txt"
    chown "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/installation-info.txt"
}

# ----------------------------
# بخش 15: تابع اصلی
# ----------------------------
main() {
    clear
    echo -e "${GREEN}\n=== شروع نصب Zhina Panel ===${NC}\n"
    
    validate_system
    install_prerequisites
    setup_directories
    setup_database
    clone_repository
    setup_virtualenv
    setup_xray
    setup_nginx
    setup_ssl
    create_database_tables
    setup_environment
    setup_panel_service
    show_installation_info
    
    echo -e "\n${GREEN}=== نصب با موفقیت کامل شد ===${NC}\n"
}

# ----------------------------
# اجرای اسکریپت
# ----------------------------
main
