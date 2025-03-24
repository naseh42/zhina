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
TEMP_DIR="/tmp/$(hostname -s)_setup_temp"

if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p $INSTALL_DIR
    chmod -R 755 $INSTALL_DIR || error "خطا در تنظیم دسترسی دایرکتوری اصلی."
fi

# استفاده از دایرکتوری موقت برای عملیات
mkdir -p $TEMP_DIR
chmod -R 755 $TEMP_DIR || error "خطا در تنظیم دسترسی دایرکتوری موقت."

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

# انتقال فایل به مسیر نهایی
mv $TEMP_DIR/.env $INSTALL_DIR/backend/.env || error "خطا در انتقال فایل .env."
chmod 600 $INSTALL_DIR/backend/.env
# تنظیم پایگاه داده
info "تنظیم پایگاه داده و کاربر..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" 2>/dev/null || info "پایگاه داده از قبل وجود دارد."
USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='vpnuser'")

if [ "$USER_EXISTS" == "1" ]; then
    info "کاربر vpnuser از قبل وجود دارد، پسورد ریست می‌شود..."
    sudo -u postgres psql -c "ALTER USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ریست پسورد کاربر vpnuser."
else
    info "ایجاد کاربر vpnuser..."
    sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ایجاد کاربر vpnuser."
fi

# اعطای دسترسی‌ها
info "ایجاد دسترسی‌ها برای کاربر vpnuser..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی‌ها."

# ایجاد اسکریپت ساخت جداول
info "ایجاد فایل اسکریپت جداول دیتابیس..."
cat <<EOF > $TEMP_DIR/setup_db.py
import psycopg2

try:
    conn = psycopg2.connect("dbname='vpndb' user='vpnuser' password='${DB_PASSWORD}' host='localhost'")
    cursor = conn.cursor()

    # ایجاد جدول کاربران
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(50) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """)

    # ایجاد جدول تنظیمات
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS settings (
        id SERIAL PRIMARY KEY,
        setting_key VARCHAR(50) UNIQUE NOT NULL,
        setting_value TEXT NOT NULL
    );
    """)

    # ایجاد جدول لاگ‌ها
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS logs (
        id SERIAL PRIMARY KEY,
        user_id INTEGER REFERENCES users(id),
        action VARCHAR(100) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """)

    conn.commit()
    cursor.close()
    conn.close()
    print("جداول با موفقیت ایجاد شدند.")

except Exception as e:
    print(f"خطا در اتصال یا ایجاد جداول: {e}")
EOF

# اجرای اسکریپت ساخت جداول
info "اجرای اسکریپت ایجاد جداول..."
if [ -f "$TEMP_DIR/setup_db.py" ]; then
    python3 $TEMP_DIR/setup_db.py || error "خطا در اجرای اسکریپت ساخت جداول."
else
    error "فایل setup_db.py پیدا نشد!"
fi
# بررسی فایل Nginx
info "بررسی و مدیریت فایل‌های Nginx..."
NGINX_CONFIG="/etc/nginx/sites-available/zhina"

if [ -f "$NGINX_CONFIG" ]; then
    info "فایل Nginx از قبل وجود دارد. حذف می‌شود..."
    rm -f $NGINX_CONFIG
fi

# ایجاد فایل جدید
info "ایجاد فایل جدید برای Nginx..."
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

# فعال‌سازی فایل تنظیمات
ln -sf $NGINX_CONFIG /etc/nginx/sites-enabled/zhina
sudo nginx -t || error "خطا در تنظیمات Nginx."
sudo systemctl reload nginx || error "خطا در راه‌اندازی مجدد Nginx."
# نصب Xray
info "نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# تنظیم فایل Xray
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
sudo systemctl restart xray || error "خطا در راه‌اندازی Xray."

# باز کردن پورت‌ها
info "باز کردن پورت‌های موردنیاز..."
PORTS=(443 8443 2083 8080 9000 1984 8989 2002)

for port in "${PORTS[@]}"; do
    ufw allow $port/tcp || info "پورت $port/tcp از قبل باز است."
    ufw allow $port/udp || info "پورت $port/udp از قبل باز است."
done
ufw reload
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
