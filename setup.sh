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
info "تنظیم دیتابیس..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" || info "پایگاه داده از قبل وجود دارد."
sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || info "کاربر از قبل وجود دارد."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی‌ها."

# ایجاد فایل requirements.txt
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
# نصب Xray
info "نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# تنظیم پروتکل‌های Xray
info "تنظیم پروتکل‌های Xray..."
VMESS_UUID=$(uuidgen)
VLESS_UUID=$(uuidgen)
TROJAN_PWD=$(openssl rand -hex 16)
HTTP_UUID=$(uuidgen)
TCP_UUID=$(uuidgen)

cat <<EOF > /etc/xray/config.json
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$VLESS_UUID", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${DOMAIN:-$(curl -s ifconfig.me)}",
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/${DOMAIN:-$(curl -s ifconfig.me)}/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/${DOMAIN:-$(curl -s ifconfig.me)}/privkey.pem"
            }
          ]
        }
      }
    },
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$VMESS_UUID"}]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "wsSettings": {"path": "/vmess"},
        "tlsSettings": {
          "serverName": "${DOMAIN:-$(curl -s ifconfig.me)}",
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/${DOMAIN:-$(curl -s ifconfig.me)}/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/${DOMAIN:-$(curl -s ifconfig.me)}/privkey.pem"
            }
          ]
        }
      }
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$TROJAN_PWD"}]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${DOMAIN:-$(curl -s ifconfig.me)}",
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/${DOMAIN:-$(curl -s ifconfig.me)}/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/${DOMAIN:-$(curl -s ifconfig.me)}/privkey.pem"
            }
          ]
        }
      }
    },
    {
      "port": 8080,
      "protocol": "http",
      "settings": {
        "clients": [{"id": "$HTTP_UUID"}]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    },
    {
      "port": 9000,
      "protocol": "tcp",
      "settings": {
        "clients": [{"id": "$TCP_UUID"}]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

info "پروتکل‌های Xray با موفقیت تنظیم شدند!"

# ایجاد فایل‌های سیستم‌مد و راه‌اندازی سرویس‌ها
info "ایجاد فایل سیستم‌مد برای Xray..."
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl start xray

info "ایجاد فایل سیستم‌مد برای Nginx..."
systemctl enable nginx
systemctl restart nginx

info "اجرای سیستم‌ها انجام شد!"

success "نصب کامل و موفقیت‌آمیز انجام شد!"
info "====== اطلاعات دسترسی ======"
echo -e "${GREEN}• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}:${PORT}${NC}"
echo -e "• یوزرنیم: ${ADMIN_USERNAME:-admin}"
echo -e "• پسورد: ${ADMIN_PASSWORD:-admin}${NC}"

info "\n====== اطلاعات پروتکل‌ها ======"
echo -e "${GREEN}🔰 VLESS:"
echo -e "  پورت: 443"
echo -e "  UUID: $VLESS_UUID${NC}"

echo -e "${GREEN}🌀 VMESS:"
echo -e "  پورت: 8443"
echo -e "  UUID: $VMESS_UUID${NC}"

echo -e "${GREEN}⚔️ Trojan:"
echo -e "  پورت: 2083"
echo -e "  پسورد: $TROJAN_PWD${NC}"

echo -e "${GREEN}🌐 HTTP:"
echo -e "  پورت: 8080"
echo -e "  UUID: $HTTP_UUID${NC}"

echo -e "${GREEN}📡 TCP:"
echo -e "  پورت: 9000"
echo -e "  UUID: $TCP_UUID${NC}"
