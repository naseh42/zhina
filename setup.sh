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
XRAY_DIR="/usr/local/bin/xray"
REPO_URL="https://github.com/naseh42/zhina.git"

# ایجاد فایل لاگ
exec > >(tee -a $LOG_FILE) 2>&1

# تابع پاکسازی
cleanup() {
    info "پاکسازی محیط..."
    rm -rf $TEMP_DIR
    rm -rf $INSTALL_DIR/venv
}

# دریافت آخرین تغییرات از گیت
info "دریافت آخرین تغییرات از گیتهاب..."
git clone $REPO_URL $TEMP_DIR || error "خطا در دریافت کدها از گیتهاب"
cd $TEMP_DIR || error "خطا در تغییر دایرکتوری"

# پیکربندی اولیه
info "بررسی و تنظیم مسیرهای نصب..."
mkdir -p $INSTALL_DIR || error "خطا در ایجاد دایرکتوری نصب"
chmod -R 750 $INSTALL_DIR || error "خطا در تنظیم مجوزهای دایرکتوری نصب"

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt-get update || error "خطا در به روزرسانی لیست پکیج‌ها"
apt-get install -y python3 python3-venv python3-pip postgresql postgresql-contrib || error "خطا در نصب پیش‌نیازها"

# دریافت اطلاعات کاربر
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " PORT
PORT=${PORT:-8000}

# تولید پسورد تصادفی
ADMIN_PASSWORD=$(openssl rand -hex 12)
DB_PASSWORD=$(openssl rand -hex 16)

# تنظیم پایگاه داده
info "تنظیم پایگاه داده..."
sudo -u postgres psql <<EOF || error "خطا در اجرای دستورات پایگاه داده"
DROP DATABASE IF EXISTS vpndb;
DROP USER IF EXISTS vpnuser;
CREATE USER vpnuser WITH PASSWORD '${DB_PASSWORD}';
CREATE DATABASE vpndb;
GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;
EOF

# تنظیمات احراز هویت PostgreSQL
echo "host all all 127.0.0.1/32 md5" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
sudo systemctl restart postgresql || error "خطا در راه‌اندازی مجدد PostgreSQL"

# ایجاد محیط مجازی پایتون
info "ایجاد محیط مجازی پایتون..."
python3 -m venv $INSTALL_DIR/venv || error "خطا در ایجاد محیط مجازی"
source $INSTALL_DIR/venv/bin/activate || error "خطا در فعال سازی محیط مجازی"

# نصب وابستگی‌های پایتون
info "نصب وابستگی‌های پایتون..."
pip install --upgrade pip || error "خطا در به روزرسانی pip"
pip install -r $TEMP_DIR/requirements.txt || error "خطا در نصب وابستگی‌ها"

# ایجاد جداول دیتابیس از مدل‌ها
info "ایجاد جداول پایگاه داده از فایل مدل‌ها..."
python3 $TEMP_DIR/backend/models.py || error "خطا در ایجاد جداول"

# پیکربندی Nginx
info "پیکربندی Nginx..."
cp $TEMP_DIR/nginx.conf /etc/nginx/sites-available/zhina || error "خطا در کپی فایل Nginx"
ln -sf /etc/nginx/sites-available/zhina /etc/nginx/sites-enabled/ || error "خطا در ایجاد لینک نمادین"
nginx -t || error "تنظیمات Nginx نامعتبر است"
systemctl restart nginx || error "خطا در راه‌اندازی مجدد Nginx"

# پاکسازی
cleanup

success "نصب با موفقیت انجام شد!"
echo -e "\n====== اطلاعات دسترسی ======"
echo "• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}:${PORT}"
echo "• یوزرنیم ادمین: admin"
echo "• پسورد ادمین: $ADMIN_PASSWORD"
echo "============================"
