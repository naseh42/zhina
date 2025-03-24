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

# تنظیم دایرکتوری نصب به‌صورت خودکار
info "بررسی و تنظیم دایرکتوری نصب..."
INSTALL_DIR="/var/lib/$(hostname -s)_setup"
if [ -d "$INSTALL_DIR" ]; then
    info "دایرکتوری نصب از قبل وجود دارد: $INSTALL_DIR"
else
    info "ایجاد دایرکتوری نصب..."
    mkdir -p $INSTALL_DIR
fi
BACKEND_DIR="$INSTALL_DIR/backend"
mkdir -p $BACKEND_DIR
chmod -R 755 $INSTALL_DIR || error "خطا در تنظیم دسترسی‌ها."

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
cat <<EOF > $BACKEND_DIR/.env
ADMIN_USERNAME='${ADMIN_USERNAME:-admin}'
ADMIN_PASSWORD='${ADMIN_PASSWORD:-admin}'
DB_PASSWORD='$DB_PASSWORD'
DATABASE_URL='postgresql://vpnuser:$DB_PASSWORD@localhost/vpndb'
EOF
chmod 600 $BACKEND_DIR/.env
# تنظیم پایگاه داده
info "تنظیم پایگاه داده و کاربر..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" 2>/dev/null || info "پایگاه داده از قبل وجود دارد."

# ایجاد یا ریست پسورد کاربر
USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='vpnuser'")
if [ "$USER_EXISTS" == "1" ]; then
    info "کاربر vpnuser از قبل وجود دارد، پسورد ریست می‌شود..."
    sudo -u postgres psql -c "ALTER USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ریست پسورد کاربر vpnuser."
else
    info "کاربر vpnuser ایجاد می‌شود..."
    sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ایجاد کاربر vpnuser."
fi

# اعطای دسترسی‌ها
info "ایجاد دسترسی‌ها از طریق Temp..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی‌ها."
# بررسی فایل Nginx و حذف خودکار در صورت وجود
info "بررسی فایل تنظیمات Nginx..."
if [ -f /etc/nginx/sites-available/zhina ]; then
    info "فایل Nginx از قبل وجود دارد. حذف می‌شود..."
    rm /etc/nginx/sites-available/zhina
fi

# ایجاد فایل تنظیمات Nginx
info "ایجاد فایل تنظیمات جدید برای Nginx..."
cat <<EOF > /etc/nginx/sites-available/zhina
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

ln -sf /etc/nginx/sites-available/zhina /etc/nginx/sites-enabled/
sudo nginx -t || error "خطا در تنظیمات Nginx."
sudo systemctl restart nginx || error "خطا در راه‌اندازی مجدد Nginx."
# تنظیم فایل Xray با تمامی پروتکل‌ها
info "تنظیم فایل Xray..."
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
    },
    {
      "port": 8080,
      "protocol": "http"
    },
    {
      "port": 9000,
      "protocol": "tcp"
    },
    {
      "port": 1984,
      "protocol": "kcp"
    },
    {
      "port": 8989,
      "protocol": "quic"
    },
    {
      "port": 2002,
      "protocol": "grpc"
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# باز کردن پورت‌ها
info "باز کردن پورت‌های موردنیاز..."
for port in 443 8443 2083 8080 9000 1984 8989 2002; do
    ufw allow ${port}/tcp
    ufw allow ${port}/udp
done
# نمایش اطلاعات دسترسی و پروتکل‌ها
success "نصب کامل و موفقیت‌آمیز انجام شد!"
info "====== اطلاعات دسترسی ======"
echo -e "${GREEN}• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}:${PORT}${NC}"
echo -e "• یوزرنیم: ${ADMIN_USERNAME:-admin}"
echo -e "• پسورد: ${ADMIN_PASSWORD:-admin}${NC}"

info "\n====== اطلاعات پروتکل‌ها ======"
echo -e "${GREEN}🔰 VLESS:"
echo -e "  پورت: 443"
echo -e "  UUID: $(uuidgen)${NC}"

echo -e "${GREEN}🌀 VMESS:"
echo -e "  پورت: 8443"
echo -e "  UUID: $(uuidgen)${NC}"

echo -e "${GREEN}⚔️ Trojan:"
echo -e "  پورت: 2083"
echo -e "  پسورد: $(openssl rand -hex 16)${NC}"

echo -e "${GREEN}🌐 HTTP:"
echo -e "  پورت: 8080${NC}"

echo -e "${GREEN}📡 TCP:"
echo -e "  پورت: 9000${NC}"

echo -e "${GREEN}💡 KCP:"
echo -e "  پورت: 1984${NC}"

echo -e "${GREEN}📶 QUIC:"
echo -e "  پورت: 8989${NC}"

echo -e "${GREEN}🔗 GRPC:"
echo -e "  پورت: 2002${NC}"

success "تمامی پروتکل‌ها تنظیم شدند و سرور آماده استفاده است!"
