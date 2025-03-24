#!/bin/bash

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# توابع نمایش پیام
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# تنظیمات اولیه
DOMAIN=""  # دامنه (اختیاری)
IP=$(hostname -I | awk '{print $1}')  # دریافت IP سرور
PORT="8000"  # پورت پیش‌فرض برای پنل
WORK_DIR="/var/lib/zhina"  # دایرکتوری کاری
BACKEND_DIR="$WORK_DIR/backend"  # دایرکتوری backend

# دریافت اطلاعات از کاربر
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " USER_PORT
[ -n "$USER_PORT" ] && PORT=$USER_PORT

read -p "یوزرنیم ادمین: " ADMIN_USERNAME
read -s -p "پسورد ادمین: " ADMIN_PASSWORD
echo ""
DB_PASSWORD=$(openssl rand -base64 12)  # تولید پسورد تصادفی برای دیتابیس

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt-get update
apt-get install -y curl wget git python3 python3-pip nginx certbot postgresql postgresql-contrib openssl python3-venv ufw

# ایجاد محیط مجازی برای پایتون
info "در حال ایجاد محیط مجازی پایتون..."
python3 -m venv $WORK_DIR/venv || error "خطا در ایجاد محیط مجازی!"
source $WORK_DIR/venv/bin/activate || error "خطا در فعال‌سازی محیط مجازی!"

# نصب کتابخانه‌های پایتون
info "در حال نصب کتابخانه‌های پایتون..."
pip install fastapi uvicorn sqlalchemy pydantic psycopg2-binary pydantic-settings || error "خطا در نصب کتابخانه‌های پایتون!"

# تنظیم PYTHONPATH
export PYTHONPATH=$WORK_DIR

# ایجاد فایل .env
info "در حال ایجاد فایل .env..."
cat <<EOF > $BACKEND_DIR/.env
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_PASSWORD=$ADMIN_PASSWORD
DB_PASSWORD=$DB_PASSWORD
DATABASE_URL=postgresql://vpnuser:$DB_PASSWORD@localhost/vpndb
EOF
chmod 600 $BACKEND_DIR/.env
success "فایل .env ایجاد شد."

# ایجاد فایل config.py
info "در حال ایجاد فایل config.py..."
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
success "فایل config.py ایجاد شد."

# نصب و تنظیم Xray
info "در حال نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install || error "خطا در نصب Xray!"

# تولید UUID و کلیدهای تصادفی
VMESS_UUID=$(uuidgen)
VLESS_UUID=$(uuidgen)
TROJAN_PASSWORD=$(openssl rand -hex 16)
SHADOWSOCKS_PASSWORD=$(openssl rand -hex 16)
HYSTERIA_OBFS=$(openssl rand -hex 8)
HYSTERIA_AUTH=$(openssl rand -hex 16)

# ایجاد کانفیگ Xray
info "در حال ایجاد کانفیگ Xray با تمام پروتکل‌ها..."
cat <<EOF > /etc/xray/config.json
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$VMESS_UUID",
                        "alterId": 64
                    }
                ]
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
            },
            "tag": "vmess-tls"
        },
        {
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$VLESS_UUID",
                        "flow": "xtls-rprx-direct"
                    }
                ],
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
            },
            "tag": "vless-xtls"
        },
        {
            "port": 2083,
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
                        "password": "$TROJAN_PASSWORD"
                    }
                ]
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
            },
            "tag": "trojan-tls"
        },
        {
            "port": 2095,
            "protocol": "shadowsocks",
            "settings": {
                "method": "aes-256-gcm",
                "password": "$SHADOWSOCKS_PASSWORD",
                "network": "tcp,udp"
            },
            "tag": "shadowsocks"
        },
        {
            "port": 2097,
            "protocol": "hysteria",
            "settings": {
                "auth_str": "$HYSTERIA_AUTH",
                "obfs": "$HYSTERIA_OBFS",
                "up_mbps": 100,
                "down_mbps": 100
            },
            "tag": "hysteria"
        },
        {
            "port": 2098,
            "protocol": "grpc",
            "settings": {
                "serviceName": "grpc-service"
            },
            "streamSettings": {
                "network": "grpc",
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
            },
            "tag": "grpc-tls"
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF

# دریافت گواهی SSL اگر دامنه وارد شده باشد
if [ -n "$DOMAIN" ]; then
    info "در حال دریافت گواهی SSL برای دامنه $DOMAIN..."
    certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN || error "خطا در دریافت گواهی SSL!"
fi

# تنظیمات دیتابیس PostgreSQL
info "در حال تنظیم دیتابیس PostgreSQL..."

sudo -u postgres psql -c "CREATE DATABASE vpndb;" || error "خطا در ایجاد پایگاه داده!"
sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ایجاد کاربر!"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی!"

# ایجاد جداول دیتابیس
info "در حال ایجاد جداول دیتابیس..."
PGPASSWORD="$DB_PASSWORD" psql -U vpnuser -d vpndb -h 127.0.0.1 -c "
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    uuid VARCHAR(255) NOT NULL,
    traffic_limit INT DEFAULT 0,
    usage_duration INT DEFAULT 0,
    simultaneous_connections INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    cdn_enabled BOOLEAN DEFAULT FALSE
);
" || error "خطا در ایجاد جداول دیتابیس!"

# تنظیمات Nginx
info "در حال تنظیم Nginx..."
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name ${DOMAIN:-$IP};

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

systemctl restart nginx || error "خطا در ری‌استارت Nginx!"

# ایجاد سرویس systemd برای Xray
info "در حال ایجاد سرویس Xray..."
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

# ایجاد سرویس systemd برای FastAPI
info "در حال ایجاد سرویس FastAPI..."
cat <<EOF > /etc/systemd/system/fastapi.service
[Unit]
Description=FastAPI Service
After=network.target

[Service]
ExecStart=$WORK_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PORT --workers 4
WorkingDirectory=$BACKEND_DIR
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# فعال‌سازی و راه‌اندازی سرویس‌ها
systemctl daemon-reload
systemctl enable xray fastapi
systemctl start xray fastapi

# باز کردن پورت‌ها در فایروال
info "در حال باز کردن پورت‌ها در فایروال..."
PORTS=(443 8443 2083 2095 2097 2098 $PORT)
for port in "${PORTS[@]}"; do
    ufw allow $port/tcp >/dev/null 2>&1
    ufw allow $port/udp >/dev/null 2>&1
    success "پورت $port در فایروال باز شد."
done

ufw --force enable >/dev/null 2>&1
success "فایروال فعال شد."

# نمایش اطلاعات نهایی
success "\n\nنصب و پیکربندی با موفقیت انجام شد!"
info "اطلاعات دسترسی به پنل:"
if [ -n "$DOMAIN" ]; then
    echo -e "${GREEN}آدرس وب پنل: https://$DOMAIN${NC}"
else
    echo -e "${GREEN}آدرس وب پنل: http://$IP:$PORT${NC}"
fi
echo -e "${GREEN}یوزرنیم: $ADMIN_USERNAME${NC}"
echo -e "${GREEN}پسورد: $ADMIN_PASSWORD${NC}"
echo -e "${GREEN}پسورد دیتابیس: $DB_PASSWORD${NC}"

info "\nاطلاعات پروتکل‌های Xray:"
echo -e "${GREEN}VMESS (TLS):"
echo -e "  پورت: 443"
echo -e "  UUID: $VMESS_UUID${NC}\n"

echo -e "${GREEN}VLESS (XTLS):"
echo -e "  پورت: 8443"
echo -e "  UUID: $VLESS_UUID${NC}\n"

echo -e "${GREEN}Trojan:"
echo -e "  پورت: 2083"
echo -e "  پسورد: $TROJAN_PASSWORD${NC}\n"

echo -e "${GREEN}Shadowsocks:"
echo -e "  پورت: 2095"
echo -e "  روش رمزنگاری: aes-256-gcm"
echo -e "  پسورد: $SHADOWSOCKS_PASSWORD${NC}\n"

echo -e "${GREEN}Hysteria:"
echo -e "  پورت: 2097"
echo -e "  Auth: $HYSTERIA_AUTH"
echo -e "  Obfs: $HYSTERIA_OBFS${NC}\n"

echo -e "${GREEN}gRPC:"
echo -e "  پورت: 2098"
echo -e "  Service Name: grpc-service${NC}"
