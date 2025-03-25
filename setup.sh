#!/bin/bash
set -euo pipefail

# ==================== تنظیمات اصلی ====================
INSTALL_DIR="/var/lib/zhina"
CONFIG_DIR="/etc/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
PANEL_PORT=8001
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -hex 8)
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
DB_PASSWORD=$(openssl rand -hex 16)
REQUIREMENTS_FILE="/tmp/zhina_requirements.txt"

# ==================== رنگ‌ها و توابع ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}[✗ ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[✓ SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[ℹ INFO] $1${NC}"; }
step() { echo -e "${BLUE}[→ STEP] $1${NC}"; }

# ==================== توابع کمکی ====================
check_root() {
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد!"
}

create_service_user() {
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER" || error "خطا در ایجاد کاربر سرویس"
    fi
}

# ==================== نصب پیش‌نیازها ====================
install_prerequisites() {
    step "نصب پیش‌نیازهای سیستم..."
    apt-get update || error "خطا در بروزرسانی لیست پکیج‌ها"
    
    apt-get install -y \
        git \
        python3 \
        python3-venv \
        python3-pip \
        postgresql \
        postgresql-contrib \
        nginx \
        curl \
        wget \
        openssl \
        unzip \
        uuid-runtime \
        virtualenv \
        certbot \
        python3-certbot-nginx || error "خطا در نصب پیش‌نیازها"
    
    success "پیش‌نیازهای سیستم با موفقیت نصب شدند"
}

# ==================== تنظیم دیتابیس ====================
setup_database() {
    step "تنظیم پایگاه داده PostgreSQL..."
    
    sudo -u postgres psql <<EOF || error "خطا در اجرای دستورات PostgreSQL"
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
    \c $DB_NAME
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF

    success "پایگاه داده با موفقیت تنظیم شد"
}

# ==================== تنظیم محیط پایتون ====================
setup_python_environment() {
    step "تنظیم محیط پایتون..."
    
    # حذف محیط مجازی قبلی اگر وجود دارد
    [ -d "$INSTALL_DIR/venv" ] && rm -rf "$INSTALL_DIR/venv"
    
    # ایجاد محیط مجازی جدید
    python3 -m venv "$INSTALL_DIR/venv" || error "خطا در ایجاد محیط مجازی"
    
    # فعال کردن محیط مجازی
    source "$INSTALL_DIR/venv/bin/activate" || error "خطا در فعال سازی محیط مجازی"
    
    # ایجاد فایل requirements
    cat > "$REQUIREMENTS_FILE" <<EOF || error "خطا در ایجاد فایل requirements"
sqlalchemy==2.0.28
psycopg2-binary==2.9.9
fastapi==0.103.2
uvicorn==0.23.2
python-multipart==0.0.6
jinja2==3.1.2
python-dotenv==1.0.0
pydantic-settings==2.0.3
pydantic[email]==2.4.2
email-validator==2.0.0
EOF

    # نصب وابستگی‌ها
    pip install --upgrade pip || error "خطا در بروزرسانی pip"
    pip install -r "$REQUIREMENTS_FILE" --no-cache-dir || error "خطا در نصب وابستگی‌های پایتون"
    
    # تست نصب ماژول‌ها
    python -c "import email_validator; import pydantic; print('ماژول‌ها با موفقیت نصب شدند')" || error "خطا در تست ماژول‌های پایتون"
    
    # غیرفعال کردن محیط مجازی
    deactivate
    
    success "محیط پایتون با موفقیت تنظیم شد"
}

# ==================== دریافت کدهای برنامه ====================
clone_repository() {
    step "دریافت کدهای برنامه..."
    
    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR"
        git pull || error "خطا در بروزرسانی کدها"
    else
        rm -rf "$INSTALL_DIR"
        git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || error "خطا در دریافت کدها"
    fi
    
    # تنظیم مجوزها
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
    
    success "کدهای برنامه با موفقیت دریافت شدند"
}

# ==================== تنظیمات دامنه و SSL ====================
configure_domain_ssl() {
    step "تنظیمات دامنه و SSL..."
    
    read -p "آیا می‌خواهید از دامنه اختصاصی استفاده کنید؟ (y/n) " USE_DOMAIN
    
    if [[ "$USE_DOMAIN" =~ ^[Yy]$ ]]; then
        read -p "لطفا نام دامنه خود را وارد کنید (مثال: panel.example.com): " PANEL_DOMAIN
        PUBLIC_IP=$(curl -s ifconfig.me)
        echo -e "\nلطفا رکورد DNS زیر را در پنل مدیریت دامنه خود تنظیم کنید:"
        echo -e "${YELLOW}${PANEL_DOMAIN} A ${PUBLIC_IP}${NC}"
        echo -e "پس از تنظیم DNS، 5 دقیقه صبر کنید و سپس Enter بزنید"
        read -p "آیا DNS را تنظیم کرده‌اید؟ (Enter) "
    else
        PANEL_DOMAIN=$(curl -s ifconfig.me)
    fi
    
    mkdir -p /etc/nginx/ssl
    
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/privkey.pem \
            -out /etc/nginx/ssl/fullchain.pem \
            -subj "/CN=${PANEL_DOMAIN}" || error "خطا در ایجاد گواهی SSL"
        SSL_TYPE="self-signed"
    else
        if certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}; then
            SSL_TYPE="letsencrypt"
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
        else
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/nginx/ssl/privkey.pem \
                -out /etc/nginx/ssl/fullchain.pem \
                -subj "/CN=${PANEL_DOMAIN}" || error "خطا در ایجاد گواهی SSL"
            SSL_TYPE="self-signed"
        fi
    fi
    
    chmod 600 /etc/nginx/ssl/*
    success "گواهی SSL با موفقیت تنظیم شد (نوع: ${SSL_TYPE})"
}

# ==================== تنظیم Nginx ====================
configure_nginx() {
    step "تنظیم Nginx..."
    
    systemctl stop xray 2>/dev/null || true
    
    rm -f /etc/nginx/sites-enabled/*
    
    cat > /etc/nginx/conf.d/panel.conf <<EOF || error "خطا در ایجاد کانفیگ Nginx"
server {
    listen 80;
    server_name ${PANEL_DOMAIN};
    
    location / {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}

server {
    listen 443 ssl;
    server_name ${PANEL_DOMAIN};
    
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    
    location / {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html
    
    nginx -t || error "خطا در کانفیگ Nginx"
    
    systemctl restart nginx
    systemctl start xray
    success "Nginx با موفقیت تنظیم شد"
}

# ==================== نصب و تنظیم Xray ====================
install_xray() {
    step "نصب و پیکربندی Xray..."
    
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"
    
    mkdir -p "$XRAY_DIR"
    wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip || error "خطا در دریافت Xray"
    unzip -o /tmp/xray.zip -d "$XRAY_DIR" || error "خطا در اکسترکت Xray"
    chmod +x "$XRAY_EXECUTABLE"

    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    
    REALITY_KEYS=$($XRAY_EXECUTABLE x25519)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)

    cat > "$XRAY_CONFIG" <<EOF || error "خطا در ایجاد کانفیگ Xray"
{
    "log": {"loglevel": "warning"},
    "inbounds": [
        {
            "port": 8443,
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
                    "serverNames": ["www.amazon.com", "${PANEL_DOMAIN}"],
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "shortIds": ["$REALITY_SHORT_ID"]
                }
            }
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

    cat > /etc/systemd/system/xray.service <<EOF || error "خطا در ایجاد سرویس Xray"
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$XRAY_DIR
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray || error "خطا در راه‌اندازی سرویس Xray"
    
    success "Xray با موفقیت نصب و پیکربندی شد"
}

# ==================== ایجاد جداول دیتابیس ====================
create_database_tables() {
    step "ایجاد جداول دیتابیس..."
    
    sudo -u postgres psql -d "$DB_NAME" <<EOF || error "خطا در ایجاد جداول دیتابیس"
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

    INSERT INTO users (username, password, is_active) 
    VALUES ('$ADMIN_USER', crypt('$ADMIN_PASS', gen_salt('bf')), true);
EOF
    
    success "جداول دیتابیس با موفقیت ایجاد شدند"
}

# ==================== تنظیم سرویس پنل ====================
setup_panel_service() {
    step "تنظیم سرویس پنل مدیریتی..."
    
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_DIR/.env" <<EOF || error "خطا در ایجاد فایل محیطی"
# تنظیمات دیتابیس
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME

# تنظیمات Xray
XRAY_UUID=$XRAY_UUID
XRAY_PATH=$XRAY_PATH
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_SHORT_ID=$REALITY_SHORT_ID
XRAY_CONFIG_PATH=/etc/xray/config.json

# تنظیمات امنیتی
SECRET_KEY=$(openssl rand -hex 32)
DEBUG=False

# تنظیمات مدیریتی
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
EOF

    chown -R "$SERVICE_USER:$SERVICE_USER" "$CONFIG_DIR"
    chmod 600 "$CONFIG_DIR/.env"
    
    cat > /etc/systemd/system/zhina-panel.service <<EOF || error "خطا در ایجاد سرویس systemd"
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
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT --workers $UVICORN_WORKERS
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
    systemctl enable zhina-panel
    
    if ! systemctl start zhina-panel; then
        journalctl -u zhina-panel -n 30 --no-pager
        error "خطا در راه‌اندازی سرویس zhina-panel"
    fi
    
    sleep 3
    if ! systemctl is-active --quiet zhina-panel; then
        journalctl -u zhina-panel -n 30 --no-pager
        error "سرویس zhina-panel پس از راه‌اندازی غیرفعال است"
    fi
    
    success "سرویس پنل مدیریتی با موفقیت تنظیم شد"
}

# ==================== تست نهایی ====================
final_test() {
    step "انجام تست‌های نهایی..."
    
    # تست اتصال به دیتابیس
    sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1" >/dev/null || error "خطا در اتصال به دیتابیس"
    
    # تست محیط پایتون
    sudo -u "$SERVICE_USER" "$INSTALL_DIR/venv/bin/python" -c "
from backend.config import settings
assert settings.DATABASE_URL.startswith('postgresql://'), 'خطا در تنظیمات دیتابیس'
print('✓ تست تنظیمات با موفقیت انجام شد')
" || error "خطا در تست نهایی پیکربندی"
    
    success "تمامی تست‌ها با موفقیت انجام شدند"
}

# ==================== نمایش اطلاعات نصب ====================
show_installation_info() {
    success "\n\n=== نصب و پیکربندی با موفقیت کامل شد ==="
    
    echo -e "\n${BLUE}══════════ اطلاعات دسترسی ══════════${NC}"
    echo -e "• آدرس پنل مدیریتی: ${GREEN}https://${PANEL_DOMAIN}${NC}"
    echo -e "• نام کاربری ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "• رمز عبور ادمین: ${YELLOW}${ADMIN_PASS}${NC}"
    
    echo -e "\n${BLUE}═════════ تنظیمات Xray ═════════${NC}"
    echo -e "• پروتکل فعال: ${YELLOW}VLESS + Reality${NC}"
    echo -e "• پورت: ${YELLOW}8443${NC}"
    echo -e "• UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• کلید عمومی Reality: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    
    echo -e "\n${BLUE}═════════ دستورات مدیریت ═════════${NC}"
    echo -e "• وضعیت سرویس: ${YELLOW}systemctl status zhina-panel${NC}"
    echo -e "• مشاهده لاگ: ${YELLOW}journalctl -u zhina-panel -f${NC}"
    echo -e "• راه‌اندازی مجدد: ${YELLOW}systemctl restart zhina-panel${NC}"
    
    echo -e "\n${GREEN}✅ نصب با موفقیت کامل شد!${NC}\n"
}

# ==================== تابع اصلی ====================
main() {
    check_root
    create_service_user
    
    install_prerequisites
    setup_database
    setup_python_environment
    clone_repository
    configure_domain_ssl
    install_xray
    create_database_tables
    setup_panel_service
    configure_nginx
    final_test
    
    show_installation_info
}

# اجرای اسکریپت
main
