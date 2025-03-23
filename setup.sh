#!/bin/bash

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

# تابع برای تولید پسورد تصادفی
generate_password() {
    echo $(openssl rand -base64 12)
}

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# تنظیمات اولیه
DOMAIN=""  # دامنه (اختیاری)
IP=$(hostname -I | awk '{print $1}')  # دریافت IP سرور
PORT="8000"  # پورت پیش‌فرض برای پنل
WORK_DIR="/var/lib/zhina"  # دایرکتوری کاری

# ایجاد دایرکتوری کاری
mkdir -p $WORK_DIR
chown -R postgres:postgres $WORK_DIR

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

# تولید پسورد تصادفی برای PostgreSQL
DB_PASSWORD=$(generate_password)

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt-get update
apt-get install -y curl wget git python3 python3-pip nginx certbot postgresql postgresql-contrib openssl python3-venv

# ایجاد محیط مجازی برای پایتون
info "در حال ایجاد محیط مجازی پایتون..."
python3 -m venv $WORK_DIR/venv || error "خطا در ایجاد محیط مجازی!"
source $WORK_DIR/venv/bin/activate || error "خطا در فعال‌سازی محیط مجازی!"

# نصب کتابخانه‌های پایتون در محیط مجازی
info "در حال نصب کتابخانه‌های پایتون..."
pip install fastapi uvicorn sqlalchemy pydantic psycopg2-binary || error "خطا در نصب کتابخانه‌های پایتون!"

# نصب Xray
info "در حال نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install || error "خطا در نصب Xray!"

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

# تنظیمات Nginx
info "در حال نصب و کانفیگ Nginx..."

if [ -n "$DOMAIN" ]; then
    SERVER_NAME="$DOMAIN"
    info "دامنه وارد شده است: $DOMAIN"
else
    SERVER_NAME="$IP"
    info "دامنه وارد نشده است. از IP سرور ($IP) استفاده می‌شود."
fi

# ایجاد فایل کانفیگ Nginx
cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name $SERVER_NAME;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# ری‌استارت Nginx
systemctl restart nginx || error "خطا در ری‌استارت Nginx!"

# دریافت گواهی SSL (فقط اگر دامنه وارد شده باشد)
if [ -n "$DOMAIN" ]; then
    info "در حال دریافت گواهی SSL برای دامنه $DOMAIN..."
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN || error "خطا در دریافت گواهی SSL!"
else
    info "در حال ایجاد گواهی خودامضا (self-signed) برای IP سرور ($IP)..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx-selfsigned.key \
        -out /etc/ssl/certs/nginx-selfsigned.crt \
        -subj "/CN=$IP" || error "خطا در ایجاد گواهی خودامضا!"

    # به‌روزرسانی فایل کانفیگ Nginx
    cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name $SERVER_NAME;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $SERVER_NAME;

    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    systemctl restart nginx || error "خطا در ری‌استارت Nginx!"
fi

# تنظیمات دیتابیس PostgreSQL
info "در حال نصب و کانفیگ دیتابیس..."

# بررسی وجود پایگاه داده و حذف آن در صورت وجود
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw vpndb; then
    info "پایگاه داده vpndb از قبل وجود دارد. در حال حذف و ایجاد مجدد..."
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS vpndb;" || error "خطا در حذف پایگاه داده vpndb!"
fi

# ایجاد پایگاه داده جدید
info "در حال ایجاد پایگاه داده vpndb..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" || error "خطا در ایجاد پایگاه داده vpndb!"

# بررسی وجود کاربر و حذف آن در صورت وجود
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='vpnuser'" | grep -q 1; then
    info "کاربر vpnuser از قبل وجود دارد. در حال حذف و ایجاد مجدد..."
    sudo -u postgres psql -c "DROP USER IF EXISTS vpnuser;" || error "خطا در حذف کاربر vpnuser!"
fi

# ایجاد کاربر جدید
info "در حال ایجاد کاربر vpnuser..."
sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ایجاد کاربر vpnuser!"

# اعطای دسترسی به کاربر
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی به کاربر vpnuser!"

# تنظیمات احراز هویت PostgreSQL
info "در حال تنظیمات احراز هویت PostgreSQL..."
cat <<EOF > /etc/postgresql/14/main/pg_hba.conf
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF

systemctl restart postgresql || error "خطا در ری‌استارت PostgreSQL!"

# ایجاد جداول دیتابیس (با استفاده از پسورد خودکار)
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

# ذخیره اطلاعات دیتابیس در فایل config.py
info "در حال ذخیره اطلاعات دیتابیس..."
cat <<EOF > $WORK_DIR/config.py
ADMIN_USERNAME = "$ADMIN_USERNAME"
ADMIN_PASSWORD = "$ADMIN_PASSWORD"
DB_PASSWORD = "$DB_PASSWORD"
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
ExecStart=$WORK_DIR/venv/bin/uvicorn main:app --host 0.0.0.0 --port $PORT --workers 4
WorkingDirectory=$WORK_DIR
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable fastapi
systemctl start fastapi

# بررسی وضعیت سرویس‌ها
info "در حال بررسی وضعیت سرویس‌ها..."
services=("xray" "fastapi" "nginx" "postgresql")
for service in "${services[@]}"; do
    systemctl is-active --quiet $service
    if [ $? -eq 0 ]; then
        success "سرویس $service با موفقیت راه‌اندازی شد."
    else
        error "سرویس $service راه‌اندازی نشد. لطفاً وضعیت سرویس را بررسی کنید."
    fi
done

# نمایش اطلاعات نهایی
success "نصب و پیکربندی با موفقیت انجام شد!"
info "اطلاعات دسترسی به پنل:"
if [ -n "$DOMAIN" ]; then
    echo -e "${GREEN}آدرس وب پنل: https://$DOMAIN${NC}"
else
    echo -e "${GREEN}آدرس وب پنل: http://$IP:$PORT${NC}"
fi
echo -e "${GREEN}یوزرنیم: $ADMIN_USERNAME${NC}"
echo -e "${GREEN}پسورد: $ADMIN_PASSWORD${NC}"
echo -e "${GREEN}پسورد دیتابیس: $DB_PASSWORD${NC}"
