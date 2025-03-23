#!/bin/bash

# تنظیمات اولیه
DOMAIN=""  # دامنه (اختیاری)
IP=$(hostname -I | awk '{print $1}')  # دریافت IP سرور
PORT="8000"  # پورت پیش‌فرض برای پنل

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# تابع برای نمایش پیام‌های خطا
error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# تابع برای نمایش پیام‌های موفقیت
success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# تابع برای نمایش پیام‌های اطلاعاتی
info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفا با دسترسی root اجرا کنید."
fi

# دریافت دامنه (اختیاری)
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN

# دریافت پورت پنل
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " USER_PORT
if [ -n "$USER_PORT" ]; then
    PORT=$USER_PORT
fi

# دریافت یوزرنیم و پسورد برای لاگین به پنل
read -p "یوزرنیم برای لاگین به پنل وارد کنید: " ADMIN_USERNAME
read -s -p "پسورد برای لاگین به پنل وارد کنید: " ADMIN_PASSWORD
echo ""

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt-get update
apt-get install -y curl wget git python3 python3-pip nginx certbot

# نصب کتابخانه‌های پایتون
info "در حال نصب کتابخانه‌های پایتون..."
pip3 install fastapi uvicorn sqlalchemy pydantic psycopg2-binary

# نصب Xray
info "در حال نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ایجاد پوشه‌های مورد نیاز
info "در حال ایجاد پوشه‌های مورد نیاز..."
mkdir -p /etc/xray /var/log/xray /usr/local/etc/xray

# کانفیگ Xray
info "در حال ایجاد کانفیگ Xray..."
cat <<EOF > /etc/xray/config.json
{
    "inbounds": [
        {
            "port": 443,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$(uuidgen)",
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
            }
        },
        {
            "port": 80,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$(uuidgen)",
                        "flow": "xtls-rprx-direct"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "none"
            }
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

# نصب و کانفیگ Nginx
info "در حال نصب و کانفیگ Nginx..."
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

systemctl restart nginx

# دریافت گواهی SSL (اگر دامنه وارد شده باشد)
if [ -n "$DOMAIN" ]; then
    info "در حال دریافت گواهی SSL برای دامنه $DOMAIN..."
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
else
    info "دامنه وارد نشده است. از IP سرور ($IP) استفاده می‌شود."
fi

# نصب و کانفیگ دیتابیس (PostgreSQL)
info "در حال نصب و کانفیگ دیتابیس..."
apt-get install -y postgresql postgresql-contrib
sudo -u postgres psql -c "CREATE DATABASE vpndb;"
sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD 'vpnpassword';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;"

# تنظیمات احراز هویت PostgreSQL
info "در حال تنظیمات احراز هویت PostgreSQL..."
cat <<EOF > /etc/postgresql/14/main/pg_hba.conf
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF

systemctl restart postgresql

# ایجاد جداول دیتابیس
info "در حال ایجاد جداول دیتابیس..."
psql -U vpnuser -d vpndb -c "
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    uuid VARCHAR(255) NOT NULL,
    traffic_limit INT DEFAULT 0,
    usage_duration INT DEFAULT 0,
    simultaneous_connections INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE
);
CREATE TABLE domains (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    cdn_enabled BOOLEAN DEFAULT FALSE
);
"

# ذخیره یوزرنیم و پسورد در فایل config.py
info "در حال ذخیره اطلاعات لاگین..."
cat <<EOF > /root/zhina/config.py
ADMIN_USERNAME = "$ADMIN_USERNAME"
ADMIN_PASSWORD = "$ADMIN_PASSWORD"
EOF

# ایجاد فایل systemd service برای Xray
info "در حال ایجاد فایل systemd service برای Xray..."
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

# ایجاد فایل systemd service برای FastAPI
info "در حال ایجاد فایل systemd service برای FastAPI..."
cat <<EOF > /etc/systemd/system/fastapi.service
[Unit]
Description=FastAPI Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /root/zhina/app.py
WorkingDirectory=/root/zhina
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fastapi
systemctl start fastapi

# نمایش اطلاعات نهایی
success "نصب و پیکربندی با موفقیت انجام شد!"
info "اطلاعات دسترسی به پنل:"
if [ -n "$DOMAIN" ]; then
    echo -e "${GREEN}آدرس وب پنل: http://$DOMAIN:$PORT${NC}"
else
    echo -e "${GREEN}آدرس وب پنل: http://$IP:$PORT${NC}"
fi
echo -e "${GREEN}یوزرنیم: $ADMIN_USERNAME${NC}"
echo -e "${GREEN}پسورد: $ADMIN_PASSWORD${NC}"
