#!/bin/bash

# فعال کردن خروج خودکار در صورت خطا
set -euo pipefail

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# توابع پیام
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# تنظیم مسیرها
INSTALL_DIR="/var/lib/zhina"
TEMP_DIR="/tmp/zhina_temp"
LOG_FILE="/var/log/zhina_install.log"
XRAY_CONFIG="/etc/xray/config.json"

# ایجاد فایل لاگ
exec > >(tee -a $LOG_FILE) 2>&1

info "شروع نصب Zhina Panel و Xray..."
mkdir -p "$INSTALL_DIR" "$TEMP_DIR"

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt-get update && apt-get install -y curl openssl nginx python3 python3-venv python3-pip postgresql postgresql-contrib unzip || error "خطا در نصب پیش‌نیازها"

# دریافت اطلاعات کاربر
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " PORT
PORT=${PORT:-8000}

# تولید پسورد تصادفی
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=$(openssl rand -hex 12)
DB_PASSWORD=$(openssl rand -hex 16)

info "ایجاد فایل پیکربندی..."
cat <<EOF > "$INSTALL_DIR/.env"
ADMIN_USERNAME='${ADMIN_USERNAME}'
ADMIN_PASSWORD='${ADMIN_PASSWORD}'
DB_PASSWORD='${DB_PASSWORD}'
DATABASE_URL='postgresql://vpnuser:${DB_PASSWORD}@localhost/vpndb'
PORT=${PORT}
DEBUG=false
EOF
chmod 600 "$INSTALL_DIR/.env"

# تنظیم پایگاه داده
info "تنظیم پایگاه داده..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'vpndb'" | grep -q 1 || sudo -u postgres psql <<EOF
CREATE ROLE vpnuser WITH LOGIN PASSWORD '${DB_PASSWORD}';
CREATE DATABASE vpndb OWNER vpnuser;
GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;
EOF

# نصب Xray
info "دانلود و نصب Xray..."
rm -rf /usr/local/bin/xray
mkdir -p /usr/local/bin/xray
curl -sL https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o "$TEMP_DIR/xray.zip" || error "خطا در دانلود Xray"
unzip -o "$TEMP_DIR/xray.zip" -d /usr/local/bin/xray || error "خطا در استخراج Xray"
chmod +x /usr/local/bin/xray/xray

# ایجاد فایل تنظیمات Xray
info "ایجاد فایل تنظیمات Xray..."
cat > "$XRAY_CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$(uuidgen)", "level": 0, "email": "user@example.com" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": { "allowInsecure": false }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF
systemctl restart xray || error "خطا در راه‌اندازی مجدد Xray"
systemctl enable xray || error "خطا در فعال‌سازی Xray"

# تنظیم Nginx
info "پیکربندی Nginx..."
cat > /etc/nginx/sites-available/zhina <<EOF
server {
    listen 80;
    server_name ${DOMAIN:-localhost};
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    access_log /var/log/nginx/zhina_access.log;
    error_log /var/log/nginx/zhina_error.log;
}
EOF

ln -sf /etc/nginx/sites-available/zhina /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t || error "تنظیمات Nginx نامعتبر است"
systemctl restart nginx || error "خطا در راه‌اندازی مجدد Nginx"

# پیکربندی فایروال
info "پیکربندی فایروال..."
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw reload
fi

# پاکسازی فایل‌های موقت
info "پاکسازی فایل‌های موقت..."
rm -rf "$TEMP_DIR"

success "نصب و تنظیم کامل شد!"
echo -e "\n====== اطلاعات دسترسی ======"
echo "• مسیر نصب: $INSTALL_DIR"
echo "• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}"
echo "• یوزرنیم ادمین: $ADMIN_USERNAME"
echo "• پسورد ادمین: $ADMIN_PASSWORD"
echo "============================"
echo "لاگ نصب در $LOG_FILE ذخیره شده است."
