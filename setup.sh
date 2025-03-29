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

# ------------------- دریافت اطلاعات ادمین -------------------
get_admin_credentials() {
    read -p "لطفا ایمیل ادمین را وارد کنید: " ADMIN_EMAIL
    while true; do
        read -sp "لطفا رمز عبور ادمین را وارد کنید (حداقل 8 کاراکتر): " ADMIN_PASS
        echo
        if [[ ${#ADMIN_PASS} -ge 8 ]]; then
            break
        else
            echo -e "${RED}رمز عبور باید حداقل 8 کاراکتر باشد!${NC}"
        fi
    done
}

# ------------------- بررسی سیستم -------------------
check_system() {
    info "بررسی پیش‌نیازهای سیستم..."
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد"
    [[ ! -f /etc/os-release ]] && error "سیستم عامل نامشخص"
    source /etc/os-release
    [[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && 
        warning "این اسکریپت فقط بر روی Ubuntu/Debian تست شده است"
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
        certbot python3-certbot-nginx jq \
        build-essential python3-dev || error "خطا در نصب پکیج‌ها"
    success "پیش‌نیازها با موفقیت نصب شدند"
}

# ------------------- تنظیم کاربر و دایرکتوری‌ها -------------------
setup_environment() {
    info "تنظیم محیط سیستم..."
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER" || 
            error "خطا در ایجاد کاربر $SERVICE_USER"
    fi
    
    mkdir -p \
        "$INSTALL_DIR" \
        "$CONFIG_DIR" \
        "$LOG_DIR/panel" \
        "$XRAY_DIR" \
        "$SECRETS_DIR" || error "خطا در ایجاد دایرکتوری‌ها"
    
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR" "$LOG_DIR" "$SECRETS_DIR"
    chmod -R 750 "$INSTALL_DIR" "$LOG_DIR" "$SECRETS_DIR"
    success "محیط سیستم تنظیم شد"
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
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF

    sudo -u postgres psql -d "$DB_NAME" <<EOF || error "خطا در ایجاد جداول"
    $(curl -s https://raw.githubusercontent.com/naseh42/zhina/main/backend/database/schema.sql)
EOF

    sudo -u postgres psql -d "$DB_NAME" <<EOF || error "خطا در ایجاد کاربر ادمین"
    INSERT INTO users (username, email, hashed_password, is_active, is_admin)
    VALUES (
        '$ADMIN_USER',
        '$ADMIN_EMAIL',
        crypt('$ADMIN_PASS', gen_salt('bf')),
        TRUE,
        TRUE
    );
EOF

    success "پایگاه داده و جداول با موفقیت ایجاد شدند"
}

# ------------------- دریافت کدها -------------------
clone_repository() {
    info "دریافت کدهای برنامه..."
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR"
        git reset --hard || error "خطا در بازنشانی تغییرات"
        git pull || error "خطا در بروزرسانی کدها"
    else
        git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || 
            error "خطا در دریافت کدها"
    fi
    
    find "$INSTALL_DIR" -type d -exec chmod 750 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 640 {} \;
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    success "کدهای برنامه دریافت شدند"
}

# ------------------- تنظیم محیط پایتون -------------------
setup_python() {
    info "تنظیم محیط پایتون..."
    python3 -m venv "$INSTALL_DIR/venv" || error "خطا در ایجاد محیط مجازی"
    source "$INSTALL_DIR/venv/bin/activate"
    
    pip install -U pip wheel || error "خطا در بروزرسانی pip"
    pip install -r "$INSTALL_DIR/requirements.txt" || error "خطا در نصب نیازمندی‌ها"
    
    deactivate
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

    REALITY_KEYS=$("$XRAY_EXECUTABLE" x25519)
    REALITY_PRIVATE_KEY=$(jq -r '.privateKey' <<< "$REALITY_KEYS")
    REALITY_PUBLIC_KEY=$(jq -r '.publicKey' <<< "$REALITY_KEYS")
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
    success "Xray با موفقیت نصب و پیکربندی شد"
}

# ------------------- تنظیم Nginx -------------------
setup_nginx() {
    info "تنظیم Nginx..."
    systemctl stop nginx 2>/dev/null || true
    
    read -p "آیا از دامنه اختصاصی استفاده می‌کنید؟ (y/n) " use_domain
    if [[ "$use_domain" =~ ^[Yy]$ ]]; then
        read -p "نام دامنه خود را وارد کنید: " domain
        PANEL_DOMAIN="$domain"
    else
        PANEL_DOMAIN="$(curl -s ifconfig.me)"
    fi

    cat > /etc/nginx/conf.d/zhina.conf <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    
    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location /static {
        alias $INSTALL_DIR/static;
    }
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF

    systemctl start nginx || error "خطا در راه‌اندازی Nginx"
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
    else
        if certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}; then
            ssl_type="letsencrypt"
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
        else
            error "خطا در دریافت گواهی Let's Encrypt"
        fi
    fi
    success "SSL تنظیم شد (نوع: $ssl_type)"
}

# ------------------- تنظیم فایل .env -------------------
setup_env_file() {
    info "تنظیم فایل محیط (.env)..."
    cat > "$INSTALL_DIR/.env" <<EOF
# تنظیمات دیتابیس
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME

# تنظیمات Xray
XRAY_UUID=$XRAY_UUID
XRAY_PATH=$XRAY_PATH
XRAY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
XRAY_PRIVATE_KEY=$REALITY_PRIVATE_KEY

# تنظیمات امنیتی
SECRET_KEY=$(openssl rand -hex 32)
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS

# تنظیمات پنل
PANEL_DOMAIN=$PANEL_DOMAIN
PANEL_PORT=$PANEL_PORT
THEME=$DEFAULT_THEME
LANGUAGE=$DEFAULT_LANGUAGE
EOF

    chown "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/.env"
    chmod 600 "$INSTALL_DIR/.env"
    success "فایل .env با موفقیت تنظیم شد"
}

# ------------------- تنظیم سرویس پنل -------------------
setup_panel_service() {
    info "تنظیم سرویس پنل..."
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn backend.app:app \\
    --host 0.0.0.0 \\
    --port $PANEL_PORT \\
    --workers $UVICORN_WORKERS \\
    --log-level info

Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/panel/access.log
StandardError=append:$LOG_DIR/panel/error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now zhina-panel || error "خطا در راه‌اندازی سرویس پنل"
    success "سرویس پنل تنظیم شد"
}

# ------------------- نمایش اطلاعات نصب -------------------
show_installation_info() {
    echo -e "\n${GREEN}=== نصب با موفقیت کامل شد ===${NC}"
    echo -e "\n${YELLOW}مشخصات دسترسی:${NC}"
    echo -e "• پنل مدیریت: ${GREEN}http://${PANEL_DOMAIN}:${PANEL_PORT}${NC}"
    echo -e "• کاربر ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "• ایمیل ادمین: ${YELLOW}${ADMIN_EMAIL}${NC}"
    
    echo -e "\n${YELLOW}تنظیمات Xray:${NC}"
    echo -e "• UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    echo -e "• Short ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
    
    echo -e "\n${YELLOW}اطلاعات دیتابیس:${NC}"
    echo -e "• نام دیتابیس: ${YELLOW}${DB_NAME}${NC}"
    echo -e "• کاربر دیتابیس: ${YELLOW}${DB_USER}${NC}"
    
    echo -e "\n${YELLOW}لاگ‌ها:${NC}"
    echo -e "• پنل: ${GREEN}tail -f $LOG_DIR/panel/*.log${NC}"
    echo -e "• Xray: ${GREEN}journalctl -u xray -f${NC}"
}

# ------------------- تابع اصلی -------------------
main() {
    check_system
    get_admin_credentials
    install_prerequisites
    setup_environment
    setup_database
    clone_repository
    setup_python
    install_xray
    setup_nginx
    setup_ssl
    setup_env_file
    setup_panel_service
    show_installation_info
}

main
