#!/bin/bash

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# توابع پیام
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# تنظیم مسیرها
INSTALL_DIR="/var/lib/zhina_setup"
TEMP_DIR="/tmp/zhina_temp"

info "بررسی و تنظیم مسیرهای نصب..."
mkdir -p $INSTALL_DIR
chmod -R 755 $INSTALL_DIR || error "خطا در تنظیم دایرکتوری نصب."
mkdir -p $TEMP_DIR
chmod -R 755 $TEMP_DIR || error "خطا در تنظیم دایرکتوری موقت."

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt update
apt install -y curl openssl nginx python3 python3-venv python3-pip postgresql postgresql-contrib certbot || error "خطا در نصب پیش‌نیازها."

# دریافت اطلاعات کاربر
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " PORT
PORT=${PORT:-8000}
read -p "یوزرنیم ادمین: " ADMIN_USERNAME
read -s -p "پسورد ادمین: " ADMIN_PASSWORD
echo ""
DB_PASSWORD=$(openssl rand -hex 12)

# تنظیم فایل .env
info "ایجاد فایل .env..."
cat <<EOF > $TEMP_DIR/.env
ADMIN_USERNAME='${ADMIN_USERNAME:-admin}'
ADMIN_PASSWORD='${ADMIN_PASSWORD:-admin}'
DB_PASSWORD='$DB_PASSWORD'
DATABASE_URL='postgresql://vpnuser:$DB_PASSWORD@localhost/vpndb'
EOF

# انتقال به مسیر نصب
mkdir -p $INSTALL_DIR/backend/
mv $TEMP_DIR/.env $INSTALL_DIR/backend/.env || error "خطا در انتقال فایل .env."
chmod 600 $INSTALL_DIR/backend/.env

# تنظیم پایگاه داده
info "تنظیم پایگاه داده و کاربر..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" 2>/dev/null || info "پایگاه داده از قبل وجود دارد."
sudo -u postgres psql -c "ALTER USER vpnuser WITH SUPERUSER;" || error "خطا در تنظیم دسترسی کاربر."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی‌ها."

# بررسی فایل‌های مدل
info "بررسی فایل‌های پروژه برای مدل‌ها..."
PROJECT_DIR="${INSTALL_DIR}/models"
if [ ! -d "$PROJECT_DIR" ]; then
    mkdir -p $PROJECT_DIR
    info "مسیر مدل‌ها ساخته شد: $PROJECT_DIR"
fi

info "جستجوی فایل‌های مدل..."
find $PROJECT_DIR -name "*.py" || error "هیچ فایلی یافت نشد!"

# تنظیم Nginx
info "بررسی و مدیریت فایل‌های Nginx..."
NGINX_CONFIG="/etc/nginx/sites-available/zhina"

rm -f /etc/nginx/sites-enabled/* || info "فایل‌های پیش‌فرض Nginx حذف شدند."
cat <<EOF > $NGINX_CONFIG
server {
    listen 80;
    server_name ${DOMAIN:-$(curl -s ifconfig.me)};
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf $NGINX_CONFIG /etc/nginx/sites-enabled/zhina
sudo nginx -t || error "خطا در تست تنظیمات Nginx."
sudo systemctl reload nginx || error "خطا در راه‌اندازی مجدد Nginx."

# تنظیم Xray
info "نصب و تنظیم Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
cat <<EOF > /etc/xray/config.json
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$(uuidgen)"}]}
    },
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$(uuidgen)"}]}
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$(openssl rand -hex 16)"}]}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

sudo systemctl restart xray || error "خطا در راه‌اندازی Xray."

# باز کردن پورت‌ها
info "باز کردن پورت‌های موردنیاز..."
PORTS=(443 8443 2083 8080 9000 1984 8989 2002)
for port in "${PORTS[@]}"; do
    ufw allow $port || info "پورت $port قبلاً باز شده است."
done
ufw reload || error "خطا در بارگذاری مجدد فایروال."

# نمایش اطلاعات دسترسی
success "نصب کامل شد!"
echo "• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}:${PORT}"
echo "• یوزرنیم: ${ADMIN_USERNAME}"
echo "• پسورد: ${ADMIN_PASSWORD}"
