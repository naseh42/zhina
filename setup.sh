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

echo "[INFO] شروع نصب Kurdan..."

# بررسی معماری سیستم
ARCH=$(uname -m)
if [[ $ARCH != "x86_64" ]]; then
    error "این اسکریپت فقط روی معماری x86_64 تست شده است."
fi

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt update && apt upgrade -y
apt install -y wget curl ufw postgresql postgresql-contrib python3-pip nginx git uuid-runtime

# تنظیمات فایروال
info "در حال تنظیم فایروال..."
ufw allow OpenSSH
ufw allow 80,443,8000/tcp
ufw enable

# دانلود و نصب XRay
info "در حال نصب XRay..."
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -O xray.zip
if [ $? -ne 0 ]; then
    error "دانلود XRay با مشکل مواجه شد."
fi
unzip -o xray.zip -d /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

# دانلود و نصب Sing-box
info "در حال نصب Sing-box..."
wget https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-amd64.tar.gz -O sing-box.tar.gz
if [ $? -ne 0 ]; then
    error "دانلود Sing-box با مشکل مواجه شد."
fi
tar -zxvf sing-box.tar.gz
mv sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box
rm -f sing-box.tar.gz

# بررسی وضعیت PostgreSQL
info "بررسی وضعیت دیتابیس PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# تنظیمات دیتابیس
DB_USER="kurdan_user"
DB_PASS=$(generate_password)  # تولید پسورد تصادفی
DB_NAME="kurdan"

info "تنظیمات دیتابیس در حال انجام است..."
sudo -u postgres psql <<EOF
ALTER USER postgres WITH PASSWORD '${DB_PASS}';
CREATE DATABASE ${DB_NAME};
CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASS}';
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

# تنظیم احراز هویت PostgreSQL
info "تنظیم احراز هویت PostgreSQL..."
cat <<EOF > /etc/postgresql/14/main/pg_hba.conf
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF
systemctl restart postgresql

# ایجاد فولدرهای XRay و Sing-box
mkdir -p /etc/xray
mkdir -p /etc/sing-box

# تولید UUID برای کانفیگ‌ها
UUID=$(uuidgen)

# ایجاد کانفیگ XRay
cat <<EOF > /etc/xray/config.json
{
  "inbounds": [
    {
      "port": 10086,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 64
          }
        ]
      }
    }
  ]
}
EOF

# ایجاد کانفیگ Sing-box
cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "output": "stdout"
  },
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "example.com",
            "port": 443,
            "users": [
              {
                "id": "${UUID}",
                "alterId": 64
              }
            ]
          }
        ]
      }
    }
  ]
}
EOF

# تنظیم سرویس‌های XRay و Sing-box
info "ایجاد سرویس‌های systemd..."
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=XRay service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -config /etc/sing-box/config.json
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
EOF

systemctl enable xray sing-box
systemctl start xray sing-box

# تنظیم دامنه برای Nginx
read -p "[INFO] دامنه خود را وارد کنید (یا Enter بزنید تا IP استفاده شود): " DOMAIN
if [ -z "$DOMAIN" ]; then
    DOMAIN=$(curl -s ifconfig.me)
    info "از IP سرور (${DOMAIN}) استفاده می‌شود."
fi

# ایجاد گواهی SSL خودامضا (اگر دامنه وارد نشده باشد)
if [ -z "$DOMAIN" ]; then
    info "در حال ایجاد گواهی خودامضا (self-signed) برای IP سرور ($DOMAIN)..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx-selfsigned.key \
        -out /etc/ssl/certs/nginx-selfsigned.crt \
        -subj "/CN=$DOMAIN" || error "خطا در ایجاد گواهی خودامضا!"
fi

# تنظیمات Nginx
cat <<EOF > /etc/nginx/sites-available/kurdan
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -s /etc/nginx/sites-available/kurdan /etc/nginx/sites-enabled/
systemctl restart nginx

# نصب FastAPI و پکیج‌های مورد نیاز
info "در حال نصب FastAPI..."
pip3 install --upgrade pip
pip3 install fastapi uvicorn sqlalchemy psycopg2-binary

# اجرای سرویس FastAPI
cat <<EOF > /etc/systemd/system/kurdan-api.service
[Unit]
Description=Kurdan FastAPI
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable kurdan-api
systemctl start kurdan-api

# ذخیره اطلاعات دیتابیس در فایل config.py
info "در حال ذخیره اطلاعات دیتابیس..."
cat <<EOF > /root/zhina/config.py
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "admin"
DB_PASSWORD = "${DB_PASS}"
EOF

success "نصب و پیکربندی Kurdan با موفقیت انجام شد!"
info "اطلاعات دسترسی:"
echo -e "${GREEN}آدرس وب پنل: http://${DOMAIN}:8000${NC}"
echo -e "${GREEN}یوزرنیم: admin${NC}"
echo -e "${GREEN}پسورد دیتابیس: ${DB_PASS}${NC}"
