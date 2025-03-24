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
apt install -y curl openssl nginx python3 python3-venv python3-pip postgresql postgresql-contrib certbot || error "خطا در نصب پیش‌نیازها."

# تنظیم دایرکتوری پروژه
WORK_DIR="/var/lib/zhina"
BACKEND_DIR="$WORK_DIR/backend"
mkdir -p $BACKEND_DIR

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
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی‌ها."
# ایجاد فایل requirements.txt
info "ایجاد فایل requirements.txt..."
cat <<EOF > $BACKEND_DIR/requirements.txt
fastapi==0.115.12
uvicorn==0.34.0
sqlalchemy==2.0.39
pydantic==2.10.6
psycopg2-binary==2.9.10
EOF
success "فایل requirements.txt ایجاد شد."

# ایجاد محیط مجازی و نصب کتابخانه‌ها
info "ایجاد محیط مجازی پایتون..."
python3 -m venv $BACKEND_DIR/venv || error "خطا در ایجاد محیط مجازی."
source $BACKEND_DIR/venv/bin/activate
pip install -r $BACKEND_DIR/requirements.txt || error "خطا در نصب کتابخانه‌ها."
deactivate

# ایجاد فایل جداول دیتابیس
info "ایجاد جداول دیتابیس..."
cat <<EOF > $BACKEND_DIR/setup_db.py
import psycopg2

conn = psycopg2.connect("dbname='vpndb' user='vpnuser' password='${DB_PASSWORD}' host='localhost'")
cursor = conn.cursor()

cursor.execute("""
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(50) NOT NULL
);
""")
conn.commit()
cursor.close()
conn.close()
EOF

# اجرای جداول دیتابیس
info "اجرای فایل ساخت جداول دیتابیس..."
python3 $BACKEND_DIR/setup_db.py || error "خطا در اجرای فایل ساخت جداول دیتابیس."
# تنظیم فایل Nginx
info "ایجاد فایل تنظیمات Nginx..."
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

ln -s /etc/nginx/sites-available/zhina /etc/nginx/sites-enabled/
sudo nginx -t || error "خطا در تنظیمات Nginx."
sudo systemctl restart nginx

# نصب Xray
info "نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# تنظیم فایل Xray با تمام پروتکل‌ها
info "تنظیم فایل Xray..."
cat <<EOF > /etc/xray/config.json
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$(uuidgen)", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      }
    },
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$(uuidgen)"}]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess"}
      }
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$(openssl rand -hex 16)"}]
      }
    },
    {
      "port": 8080,
      "protocol": "http",
      "settings": {}
    },
    {
      "port": 9000,
      "protocol": "tcp",
      "settings": {}
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
sudo systemctl restart xray
# ایجاد فایل systemd برای Uvicorn
info "ایجاد فایل سرویس Uvicorn..."
cat <<EOF > /etc/systemd/system/uvicorn.service
[Unit]
Description=Uvicorn Server
After=network.target

[Service]
WorkingDirectory=$BACKEND_DIR
ExecStart=$BACKEND_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PORT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# راه‌اندازی سرویس‌ها
sudo systemctl daemon-reload
sudo systemctl enable uvicorn
sudo systemctl start uvicorn
sudo systemctl enable xray
sudo systemctl start xray

# نمایش اطلاعات دسترسی
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

echo -e "${GREEN}
