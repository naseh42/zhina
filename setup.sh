#!/bin/bash
set -euo pipefail
exec > >(tee -a "/var/log/zhina-install.log") 2>&1

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina"
CONFIG_DIR="/etc/zhina"
LOG_DIR="/var/log/zhina"
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
XRAY_HTTP_PORT=8080
DB_PASSWORD=$(openssl rand -hex 16)

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033'
NC='\033[0m'

error() { 
    echo -e "${RED}[✗] $1${NC}" >&2
    echo -e "برای مشاهده خطاهای کامل، فایل لاگ را بررسی کنید: ${YELLOW}/var/log/zhina-install.log${NC}"
    exit 1
}
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }
warning() { echo -e "${YELLOW}[!] $1${NC}"; }

# ------------------- بررسی سیستم -------------------
check_system() {
    info "بررسی پیش‌نیازهای سیستم..."
    
    # بررسی دسترسی root
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد"
    
    # بررسی سیستم عامل
    if [[ ! -f /etc/os-release ]]; then
        error "سیستم عامل نامشخص"
    fi
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
        certbot python3-certbot-nginx || error "خطا در نصب پکیج‌ها"
    
    success "پیش‌نیازها با موفقیت نصب شدند"
}

# ------------------- تنظیم کاربر و دایرکتوری‌ها -------------------
setup_environment() {
    info "تنظیم محیط سیستم..."
    
    # ایجاد کاربر سرویس
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER" || 
            error "خطا در ایجاد کاربر $SERVICE_USER"
    fi
    
    # ایجاد دایرکتوری‌ها
    mkdir -p \
        "$INSTALL_DIR" \
        "$CONFIG_DIR" \
        "$LOG_DIR" \
        "$XRAY_DIR" || error "خطا در ایجاد دایرکتوری‌ها"
    
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
    chmod 750 "$INSTALL_DIR"
    
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
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    \c $DB_NAME
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF
    
    # تنظیمات امنیتی PostgreSQL
    local pg_conf="/etc/postgresql/$(ls /etc/postgresql)/main/postgresql.conf"
    sed -i '/^#listen_addresses/s/^#//; s/localhost/*/' "$pg_conf"
    echo "host $DB_NAME $DB_USER 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
    
    systemctl restart postgresql || error "خطا در راه‌اندازی مجدد PostgreSQL"
    
    success "پایگاه داده تنظیم شد"
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
    
    # تنظیم مجوزها
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
    
    # نصب نیازمندی‌ها
    cat > "$INSTALL_DIR/requirements.txt" <<EOF
fastapi==0.103.2
uvicorn==0.23.2
sqlalchemy==2.0.28
psycopg2-binary==2.9.9
python-dotenv==1.0.0
pydantic-settings==2.0.3
python-multipart==0.0.6
jinja2==3.1.2
EOF
    
    pip install -U pip wheel || error "خطا در بروزرسانی pip"
    pip install -r "$INSTALL_DIR/requirements.txt" || error "خطا در نصب نیازمندی‌ها"
    deactivate
    
    success "محیط پایتون تنظیم شد"
}

# ------------------- نصب Xray -------------------
install_xray() {
    info "نصب و پیکربندی Xray..."
    
    systemctl stop xray 2>/dev/null || true
    
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
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"

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

    # ایجاد سرویس systemd
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
    
    # تنظیم دامنه
    read -p "آیا از دامنه اختصاصی استفاده می‌کنید؟ (y/n) " use_domain
    if [[ "$use_domain" =~ ^[Yy]$ ]]; then
        read -p "نام دامنه خود را وارد کنید: " domain
        PANEL_DOMAIN="$domain"
    else
        PANEL_DOMAIN="$(curl -s ifconfig.me)"
    fi

    # ایجاد کانفیگ Nginx
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

    # راه‌اندازی مجدد Nginx
    systemctl start nginx || error "خطا در راه‌اندازی Nginx"
    
    success "Nginx با موفقیت پیکربندی شد"
}

# ------------------- تنظیم SSL -------------------
setup_ssl() {
    info "تنظیم گواهی SSL..."
    
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # گواهی خودامضا برای IP
        mkdir -p /etc/nginx/ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/privkey.pem \
            -out /etc/nginx/ssl/fullchain.pem \
            -subj "/CN=$PANEL_DOMAIN"
        ssl_type="self-signed"
    else
        # Let's Encrypt
        if certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}; then
            ssl_type="letsencrypt"
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
        else
            error "خطا در دریافت گواهی Let's Encrypt"
        fi
    fi
    
    success "SSL تنظیم شد (نوع: $ssl_type)"
}

# ------------------- تنظیم سرویس پنل -------------------
setup_panel_service() {
    info "تنظیم سرویس پنل..."
    
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT
Restart=always

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
    echo -e "• رمز عبور: ${YELLOW}${ADMIN_PASS}${NC}"
    
    echo -e "\n${YELLOW}تنظیمات Xray:${NC}"
    echo -e "• UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    echo -e "• Short ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
    echo -e "• مسیر WS: ${YELLOW}${XRAY_PATH}${NC}"
    
    echo -e "\n${YELLOW}دستورات مدیریت:${NC}"
    echo -e "• وضعیت سرویس‌ها: ${GREEN}systemctl status xray nginx zhina-panel${NC}"
    echo -e "• مشاهده لاگ: ${GREEN}journalctl -u xray -f${NC}"
    
    # ذخیره اطلاعات در فایل
    cat > "$INSTALL_DIR/installation-info.txt" <<EOF
=== Zhina Panel Installation Details ===

Panel URL: http://${PANEL_DOMAIN}:${PANEL_PORT}
Admin Username: ${ADMIN_USER}
Admin Password: ${ADMIN_PASS}

Xray Settings:
- VLESS+Reality:
  • Port: 8443
  • UUID: ${XRAY_UUID}
  • Public Key: ${REALITY_PUBLIC_KEY}
  • Short ID: ${REALITY_SHORT_ID}
- VMESS+WS:
  • Port: ${XRAY_HTTP_PORT}
  • Path: ${XRAY_PATH}

Database Info:
- Username: ${DB_USER}
- Password: ${DB_PASSWORD}
- Database: ${DB_NAME}
EOF

    chmod 600 "$INSTALL_DIR/installation-info.txt"
}

# ------------------- تابع اصلی -------------------
main() {
    check_system
    install_prerequisites
    setup_environment
    setup_database
    clone_repository
    setup_python
    install_xray
    setup_nginx
    setup_ssl
    setup_panel_service
    show_installation_info
    
    echo -e "\n${GREEN}برای مشاهده جزئیات کامل، فایل لاگ را بررسی کنید:${NC}"
    echo -e "${YELLOW}tail -f /var/log/zhina-install.log${NC}"
}

main
