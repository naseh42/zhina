#!/bin/bash

# تنظیمات رنگ برای پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# توابع نمایش پیام
error() { echo -e "${RED}[!] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[+] $1${NC}"; }
info() { echo -e "${YELLOW}[*] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید: sudo ./install.sh"
fi

# تنظیمات اصلی
DOMAIN=""
IP=$(hostname -I | awk '{print $1}')
PORT="8000"
WORK_DIR="/var/lib/zhina"
BACKEND_DIR="$WORK_DIR/backend"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=$(openssl rand -hex 12)
DB_PASSWORD=$(openssl rand -hex 16)

# دریافت اطلاعات
read -p "دامنه (اختیاری): " DOMAIN
read -p "پورت پنل [8000]: " USER_PORT
[ -n "$USER_PORT" ] && PORT=$USER_PORT

# 1. نصب پیش‌نیازها
info "نصب بسته‌های مورد نیاز..."
apt-get update
apt-get install -y curl wget git python3 python3-pip nginx certbot postgresql postgresql-contrib openssl python3-venv ufw

# 2. تنظیم محیط کار
info "تنظیم محیط..."
mkdir -p $BACKEND_DIR
chown -R postgres:postgres $WORK_DIR
chmod -R 750 $WORK_DIR

# 3. تنظیم دیتابیس
info "تنظیم PostgreSQL..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" 2>/dev/null || info "پایگاه داده وجود دارد"
sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || info "کاربر وجود دارد"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;"

# 4. فایل‌های پیکربندی
info "ایجاد فایل‌های پیکربندی..."

# فایل .env
cat <<EOF > $BACKEND_DIR/.env
ADMIN_USERNAME='$ADMIN_USERNAME'
ADMIN_PASSWORD='$ADMIN_PASSWORD'
DB_PASSWORD='$DB_PASSWORD'
DATABASE_URL='postgresql://vpnuser:$DB_PASSWORD@localhost/vpndb'
EOF
chmod 600 $BACKEND_DIR/.env

# فایل config.py
cat <<EOF > $BACKEND_DIR/config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    admin_username: str
    admin_password: str
    db_password: str
    database_url: str

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
EOF

# 5. نصب Xray
info "نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# تولید کلیدها
VMESS_UUID=$(uuidgen)
VLESS_UUID=$(uuidgen)
TROJAN_PASSWORD=$(openssl rand -hex 16)
SHADOWSOCKS_PASSWORD=$(openssl rand -hex 16)

# فایل config.json
cat <<EOF > /etc/xray/config.json
{
    "log": {"loglevel": "warning"},
    "inbounds": [
        {
            "port": 443,
            "protocol": "vmess",
            "settings": {
                "clients": [{"id": "$VMESS_UUID", "alterId": 64}]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$DOMAIN",
                    "certificates": [
                        {
                            "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
                            "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                        }
                    ]
                }
            }
        },
        {
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "$VLESS_UUID", "flow": "xtls-rprx-direct"}]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "serverName": "$DOMAIN",
                    "certificates": [
                        {
                            "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
                            "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                        }
                    ]
                }
            }
        },
        {
            "port": 2083,
            "protocol": "trojan",
            "settings": {
                "clients": [{"password": "$TROJAN_PASSWORD"}]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$DOMAIN",
                    "certificates": [
                        {
                            "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
                            "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                        }
                    ]
                }
            }
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

# 6. فعال‌سازی سرویس‌ها
info "فعال‌سازی سرویس‌ها..."

# سرویس Xray
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

# سرویس FastAPI
cat <<EOF > /etc/systemd/system/fastapi.service
[Unit]
Description=FastAPI Service
After=network.target
[Service]
ExecStart=$WORK_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PORT
WorkingDirectory=$BACKEND_DIR
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray fastapi nginx postgresql
systemctl restart xray fastapi nginx postgresql

# 7. فایروال
info "تنظیم فایروال..."
ufw allow 22,80,443,8443,2083,$PORT/tcp
ufw --force enable

# 8. اطلاعات نهایی
success "\n\nنصب کامل شد!"
info "اطلاعات دسترسی:"
echo -e "${GREEN}پنل مدیریت: http://${DOMAIN:-$IP}:$PORT${NC}"
echo -e "${GREEN}یوزرنیم: $ADMIN_USERNAME${NC}"
echo -e "${GREEN}پسورد: $ADMIN_PASSWORD${NC}"

info "\nاطلاعات پروتکل‌ها:"
echo -e "${GREEN}VMESS:"
echo -e "  پورت: 443\n  UUID: $VMESS_UUID${NC}"
echo -e "${GREEN}VLESS:"
echo -e "  پورت: 8443\n  UUID: $VLESS_UUID${NC}"
echo -e "${GREEN}Trojan:"
echo -e "  پورت: 2083\n  پسورد: $TROJAN_PASSWORD${NC}"
