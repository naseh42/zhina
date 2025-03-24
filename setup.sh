#!/bin/bash

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# توابع نمایش پیام
error() { echo -e "${RED}[!] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[+] $1${NC}"; }
info() { echo -e "${YELLOW}[*] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# تنظیمات اولیه
DOMAIN=""
IP=$(hostname -I | awk '{print $1}')
PORT="8000"
WORK_DIR="/var/lib/zhina"
BACKEND_DIR="$WORK_DIR/backend"

# دریافت اطلاعات از کاربر
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " USER_PORT
[ -n "$USER_PORT" ] && PORT=$USER_PORT

read -p "یوزرنیم ادمین: " ADMIN_USERNAME
read -s -p "پسورد ادمین: " ADMIN_PASSWORD
echo ""
DB_PASSWORD=$(openssl rand -base64 12)

# 1. نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt-get update
apt-get install -y curl wget git python3 python3-pip nginx certbot postgresql postgresql-contrib openssl python3-venv ufw

# 2. تنظیم محیط کار
info "تنظیم محیط کار..."
mkdir -p $BACKEND_DIR
chown -R postgres:postgres $WORK_DIR
chmod -R 755 $WORK_DIR

# 3. تنظیمات دیتابیس
info "تنظیمات PostgreSQL..."

# ایجاد دیتابیس و کاربر
sudo -u postgres psql -c "CREATE DATABASE vpndb;" 2>/dev/null || info "دیتابیس از قبل وجود دارد"
sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || info "کاربر از قبل وجود دارد"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;"

# 4. ایجاد فایل‌های پیکربندی
info "ایجاد فایل‌های پیکربندی..."

# فایل .env
cat <<EOF > $BACKEND_DIR/.env
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_PASSWORD=$ADMIN_PASSWORD
DB_PASSWORD=$DB_PASSWORD
DATABASE_URL=postgresql://vpnuser:$DB_PASSWORD@localhost/vpndb
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

# 5. نصب و تنظیم Xray
info "نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# تولید کلیدها
VMESS_UUID=$(uuidgen)
VLESS_UUID=$(uuidgen)
TROJAN_PASSWORD=$(openssl rand -hex 16)
SHADOWSOCKS_PASSWORD=$(openssl rand -hex 16)
HYSTERIA_OBFS=$(openssl rand -hex 8)
HYSTERIA_AUTH=$(openssl rand -hex 16)

# فایل کانفیگ Xray
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
                "clients": [{"id": "$VLESS_UUID", "flow": "xtls-rprx-direct"}],
                "decryption": "none"
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
        },
        {
            "port": 2095,
            "protocol": "shadowsocks",
            "settings": {
                "method": "aes-256-gcm",
                "password": "$SHADOWSOCKS_PASSWORD",
                "network": "tcp,udp"
            }
        },
        {
            "port": 2097,
            "protocol": "hysteria",
            "settings": {
                "auth_str": "$HYSTERIA_AUTH",
                "obfs": "$HYSTERIA_OBFS",
                "up_mbps": 100,
                "down_mbps": 100
            }
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

# 6. تنظیمات Nginx
info "تنظیم Nginx..."
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name ${DOMAIN:-$IP};
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# 7. سرویس‌های systemd
info "ایجاد سرویس‌ها..."

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

# 8. فعال‌سازی سرویس‌ها
systemctl daemon-reload
systemctl enable xray fastapi nginx postgresql
systemctl restart xray fastapi nginx postgresql

# 9. تنظیم فایروال
info "تنظیم فایروال..."
ufw allow 22,80,443,8443,2083,2095,2097,2098,${PORT}/tcp
ufw --force enable

# 10. نمایش اطلاعات نهایی
success "\n\nنصب با موفقیت انجام شد!"
info "اطلاعات دسترسی:"
echo -e "${GREEN}پنل مدیریت: ${DOMAIN:-http://$IP:$PORT}${NC}"
echo -e "${GREEN}یوزرنیم: $ADMIN_USERNAME${NC}"
echo -e "${GREEN}پسورد: $ADMIN_PASSWORD${NC}"

info "\nاطلاعات پروتکل‌ها:"
echo -e "${GREEN}VMESS:"
echo -e "  پورت: 443\n  UUID: $VMESS_UUID${NC}"
echo -e "${GREEN}VLESS:"
echo -e "  پورت: 8443\n  UUID: $VLESS_UUID${NC}"
echo -e "${GREEN}Trojan:"
echo -e "  پورت: 2083\n  پسورد: $TROJAN_PASSWORD${NC}"
