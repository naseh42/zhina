#!/bin/bash
# ===============================================
# نام اسکریپت: نصب کامل Zhina Panel + Xray-core (نسخه اصلاح شده)
# نسخه: 4.2.2
# تاریخ آخرین بروزرسانی: 2024-03-26
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
XRAY_PORT=8443          # پورت اصلی Xray برای HTTPS
XRAY_HTTP_PORT=8080     # پورت جدید برای HTTP (جایگزین 80)
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
    
    [[ ! -f /etc/os-release ]] && error "سیستم عامل نامشخص"
    
    source /etc/os-release
    [[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && 
        warning "این اسکریپت فقط بر روی Ubuntu/Debian تست شده است"
    
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد"
    
    local mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    (( mem < 1000000 )) && warning "حداقل 1GB RAM توصیه می‌شود"
    
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
    
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow $XRAY_PORT
    ufw allow $XRAY_HTTP_PORT
    ufw --force enable
    
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    systemctl restart fail2ban
    
    success "پیش‌نیازها با موفقیت نصب شدند"
}

# ----------------------------
# بخش 4: تنظیم کاربر و دایرکتوری‌ها
# ----------------------------
setup_directories() {
    info "تنظیم دایرکتوری‌ها و کاربر سیستم..."
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"
    fi
    
    mkdir -p \
        "$INSTALL_DIR" \
        "$CONFIG_DIR" \
        "$LOG_DIR" \
        "$XRAY_DIR" \
        "$INSTALL_DIR/backend" \
        "$INSTALL_DIR/frontend/static" \
        "$INSTALL_DIR/frontend/templates"
    
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    chmod 750 "$INSTALL_DIR"
    
    success "دایرکتوری‌ها و کاربر سیستم تنظیم شدند"
}

# ----------------------------
# بخش 5: تنظیم دیتابیس PostgreSQL
# ----------------------------
setup_database() {
    info "تنظیم پایگاه داده PostgreSQL..."
    
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
    
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install --upgrade pip wheel setuptools
    pip install -r "$INSTALL_DIR/requirements.txt"
    deactivate
    
    success "محیط مجازی Python تنظیم شد"
}

# ----------------------------
# بخش 8: نصب و پیکربندی Xray-core (نسخه اصلاح شده)
# ----------------------------
setup_xray() {
    info "نصب و پیکربندی Xray..."
    
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"/*
    mkdir -p "$XRAY_DIR"
    
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
    REALITY_SHORT_ID=$(openssl rand -hex 8)

    # ایجاد کانفیگ Xray با پورت‌های اصلاح شده
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
    
    systemctl daemon-reload
    systemctl enable --now xray
    
    if ! systemctl is-active --quiet xray; then
        journalctl -u xray -n 50 --no-pager
        error "سرویس Xray راه‌اندازی نشد"
    fi
    
    success "Xray با موفقیت نصب و پیکربندی شد"
}

# ----------------------------
# بخش 9: تنظیمات Nginx (نسخه اصلاح شده)
# ----------------------------
setup_nginx() {
    info "تنظیم Nginx..."
    
    systemctl stop nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/*
    rm -f /etc/nginx/conf.d/*
    
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
    
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    systemctl start nginx
    
    if ! systemctl is-active --quiet nginx; then
        journalctl -u nginx -n 50 --no-pager
        error "سرویس Nginx راه‌اندازی نشد"
    fi
    
    success "Nginx با موفقیت پیکربندی شد"
}

# ----------------------------
# بخش 10: تنظیمات SSL (بهینه شده)
# ----------------------------
setup_ssl() {
    info "تنظیم گواهی SSL..."
    
    if ! command -v certbot &>/dev/null; then
        apt-get install -y certbot python3-certbot-nginx
    fi
    
    read -p "آیا دامنه ثبت شده دارید؟ (y/n) " has_domain
    if [[ "$has_domain" =~ ^[Yy]$ ]]; then
        read -p "نام دامنه خود را وارد کنید: " domain_name
        if certbot --nginx --non-interactive --agree-tos --email admin@$domain_name -d $domain_name; then
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
            success "گواهی SSL از Let's Encrypt دریافت شد"
            ssl_cert_path="/etc/letsencrypt/live/$domain_name/fullchain.pem"
            ssl_key_path="/etc/letsencrypt/live/$domain_name/privkey.pem"
        else
            warning "دریافت گواهی SSL ناموفق بود، استفاده از خودامضا"
            create_self_signed_cert
        fi
    else
        warning "استفاده از گواهی خودامضا برای IP سرور"
        create_self_signed_cert
    fi
    
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
        proxy_pass http://127.0.0.1:$XRAY_HTTP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    
    systemctl restart nginx
    success "تنظیمات SSL کامل شد"
}

create_self_signed_cert() {
    mkdir -p /etc/nginx/ssl
    ssl_cert_path="/etc/nginx/ssl/fullchain.pem"
    ssl_key_path="/etc/nginx/ssl/privkey.pem"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout $ssl_key_path \
        -out $ssl_cert_path \
        -subj "/CN=$(curl -s ifconfig.me)"
}

# ----------------------------
# بخش 11-15: سایر بخش‌ها بدون تغییر
# ----------------------------
# [کدهای بخش‌های 11 تا 15 بدون تغییر از اسکریپت اصلی باقی می‌مانند]
# ----------------------------

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

# اجرای اسکریپت
main
