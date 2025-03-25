#!/bin/bash
set -euo pipefail

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
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
    apt-get install -y git python3 python3-venv python3-pip postgresql nginx curl wget openssl unzip uuid-runtime tree
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
    sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    success "پایگاه داده با موفقیت تنظیم شد!"
}

setup_requirements() {
    info "نصب وابستگی‌های پایتون..."
    python3 -m venv $INSTALL_DIR/venv
    source $INSTALL_DIR/venv/bin/activate
    pip install -U pip setuptools wheel
    pip install -r $INSTALL_DIR/requirements.txt
    deactivate
    success "وابستگی‌ها با موفقیت نصب شدند!"
}

install_xray() {
    info "نصب و پیکربندی Xray..."
    
    # حذف نسخه قبلی اگر وجود دارد
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"
    
    # ایجاد دایرکتوری و دانلود Xray
    mkdir -p "$XRAY_DIR"
    wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d "$XRAY_DIR"
    chmod +x "$XRAY_EXECUTABLE"

    # آزادسازی پورت 443 اگر در حال استفاده است
    if ss -tulnp | grep -q ':443 '; then
        info "آزادسازی پورت 443..."
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl stop apache2 2>/dev/null || true
    fi

    # تولید مقادیر تصادفی
    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    REALITY_KEY=$($XRAY_EXECUTABLE x25519 | awk '/Private key:/ {print $3}')

    # ایجاد فایل کانفیگ Xray
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [
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
                    "serverNames": ["www.amazon.com"],
                    "privateKey": "$REALITY_KEY",
                    "shortIds": ["$(openssl rand -hex 8)"]
                }
            }
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
    success "Xray با موفقیت نصب و پیکربندی شد!"
}

setup_panel() {
    info "تنظیم پنل مدیریت..."
    
    # ایجاد فایل سرویس پنل
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT --workers $UVICORN_WORKERS
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # تنظیم مجوزها
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    chmod -R 755 $INSTALL_DIR

    systemctl daemon-reload
    systemctl enable zhina-panel
    systemctl start zhina-panel
    success "پنل مدیریت با موفقیت تنظیم شد!"
}

show_info() {
    PUBLIC_IP=$(curl -s ifconfig.me)
    success "\n\n=== نصب کامل شد! ==="
    echo -e "دسترسی پنل مدیریتی:"
    echo -e "• آدرس: http://${PUBLIC_IP}:${PANEL_PORT}"
    echo -e "• یوزرنیم ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "• پسورد ادمین: ${YELLOW}${ADMIN_PASS}${NC}"

    echo -e "\nتنظیمات Xray:"
    echo -e "• پروتکل فعال: ${YELLOW}VLESS + Reality${NC} (پورت 443)"
    echo -e "• UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• کلید عمومی Reality: ${YELLOW}$($XRAY_EXECUTABLE x25519 | awk '/Public key:/ {print $3}')${NC}"

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
    success "کدهای برنامه با موفقیت دریافت شدند!"

    # 5. نصب وابستگی‌ها
    setup_requirements

    # 6. نصب Xray
    install_xray

    # 7. تنظیم پنل
    setup_panel

    # 8. نمایش اطلاعات
    show_info
}

main
