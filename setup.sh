#!/bin/bash

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# توابع نمایش پیام
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt update
apt install -y git curl openssl nginx python3 python3-venv python3-pip postgresql postgresql-contrib certbot || error "خطا در نصب پیش‌نیازها."

# تنظیم دایرکتوری پروژه
WORK_DIR="/var/lib/zhina"
BACKEND_DIR="$WORK_DIR/backend"
mkdir -p $BACKEND_DIR

# کلون کردن پروژه
info "کلون کردن مخزن..."
git clone https://github.com/naseh42/zhina.git $WORK_DIR || error "خطا در کلون کردن مخزن."

# ساخت فایل requirements.txt
info "ایجاد فایل requirements.txt..."
cat <<EOF > $BACKEND_DIR/requirements.txt
fastapi==0.115.12
uvicorn==0.34.0
sqlalchemy==2.0.39
pydantic==2.10.6
psycopg2-binary==2.9.10
pydantic-settings==2.8.1
EOF
success "فایل requirements.txt ایجاد شد."

# ایجاد محیط مجازی و نصب کتابخانه‌ها
info "ایجاد محیط مجازی پایتون..."
python3 -m venv $BACKEND_DIR/venv || error "خطا در ایجاد محیط مجازی."
source $BACKEND_DIR/venv/bin/activate
info "در حال نصب کتابخانه‌های پایتون..."
pip install -r $BACKEND_DIR/requirements.txt || error "خطا در نصب کتابخانه‌ها."
deactivate

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
cat <<EOF > $BACKEND_DIR/.env
ADMIN_USERNAME='${ADMIN_USERNAME:-admin}'
ADMIN_PASSWORD='${ADMIN_PASSWORD:-admin}'
DB_PASSWORD='$DB_PASSWORD'
DATABASE_URL='postgresql://vpnuser:$DB_PASSWORD@localhost/vpndb'
EOF
chmod 600 $BACKEND_DIR/.env

# تنظیم دیتابیس
info "تنظیم دیتابیس..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" || info "پایگاه داده از قبل وجود دارد."
sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || info "کاربر از قبل وجود دارد."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی‌ها."

# ایجاد جداول دیتابیس
info "ایجاد جداول دیتابیس..."
source $BACKEND_DIR/venv/bin/activate
python3 $BACKEND_DIR/setup_db.py || error "خطا در ایجاد جداول دیتابیس."
deactivate

# نصب Xray
info "نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# تنظیم پروتکل‌های Xray
info "تنظیم پروتکل‌های Xray..."
VMESS_UUID=$(uuidgen)
VLESS_UUID=$(uuidgen)
TROJAN_PWD=$(openssl rand -hex 16)
cat <<EOF > /etc/xray/config.json
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": 443,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$VMESS_UUID"}]}
    },
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$VLESS_UUID"}]}
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$TROJAN_PWD"}]}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# تنظیم Nginx
info "تنظیم Nginx..."
cat <<EOF > /etc/nginx/sites-available/zhina
server {
    listen 80;
    server_name ${DOMAIN:-$(curl -s ifconfig.me)};

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
ln -s /etc/nginx/sites-available/zhina /etc/nginx/sites-enabled/
systemctl restart nginx

# نمایش اطلاعات نهایی
success "نصب با موفقیت انجام شد!"
info "====== اطلاعات دسترسی ======"
echo -e "${GREEN}• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}:${PORT}${NC}"
echo -e "• یوزرنیم: ${ADMIN_USERNAME:-admin}"
echo -e "• پسورد: ${ADMIN_PASSWORD:-admin}${NC}"
