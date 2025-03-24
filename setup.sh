#!/bin/bash

# فعال کردن خروج خودکار در صورت خطا
set -euo pipefail

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# توابع پیام
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# تنظیم مسیرها
INSTALL_DIR="/var/lib/zhina"
TEMP_DIR="/tmp/zhina_temp"
LOG_FILE="/var/log/zhina_install.log"
XRAY_DIR="/usr/local/bin/xray"

# ایجاد فایل لاگ
exec > >(tee -a $LOG_FILE) 2>&1

info "شروع نصب Zhina Panel و Xray..."
info "بررسی و تنظیم مسیرهای نصب..."
mkdir -p $INSTALL_DIR || error "خطا در ایجاد دایرکتوری نصب"
mkdir -p $TEMP_DIR || error "خطا در ایجاد دایرکتوری موقت"
chmod -R 750 $INSTALL_DIR || error "خطا در تنظیم مجوزهای دایرکتوری نصب"
chmod -R 750 $TEMP_DIR || error "خطا در تنظیم مجوزهای دایرکتوری موقت"

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt-get update || error "خطا در به روزرسانی لیست پکیج‌ها"
apt-get install -y curl wget openssl nginx python3 python3-venv python3-pip postgresql postgresql-contrib unzip || error "خطا در نصب پیش‌نیازها"

# دریافت اطلاعات کاربر
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " PORT
PORT=${PORT:-8000}

# تولید پسورد تصادفی برای ادمین
ADMIN_USERNAME="admin"
ADMIN_PASSWORD=$(openssl rand -hex 12)
DB_PASSWORD=$(openssl rand -hex 16)

info "در حال ایجاد فایل پیکربندی..."
cat <<EOF > $TEMP_DIR/.env
# تنظیمات ادمین
ADMIN_USERNAME='${ADMIN_USERNAME}'
ADMIN_PASSWORD='${ADMIN_PASSWORD}'

# تنظیمات پایگاه داده
DB_PASSWORD='${DB_PASSWORD}'
DATABASE_URL='postgresql://vpnuser:${DB_PASSWORD}@127.0.0.1/vpndb'

# تنظیمات برنامه
PORT=${PORT}
DEBUG=false
EOF

mv $TEMP_DIR/.env $INSTALL_DIR/.env || error "خطا در انتقال فایل .env"
chmod 600 $INSTALL_DIR/.env || error "خطا در تنظیم مجوز فایل .env"

# تنظیم پایگاه داده
info "تنظیم پایگاه داده و کاربر..."
cd /tmp || error "خطا در تغییر دایرکتوری"

sudo -u postgres psql <<EOF || error "خطا در اجرای دستورات پایگاه داده"
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vpnuser') THEN
        CREATE ROLE vpnuser WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
END \$\$;

CREATE DATABASE vpndb;
GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;
EOF

# تنظیمات احراز هویت PostgreSQL
echo "host all all 127.0.0.1/32 md5" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
sudo systemctl restart postgresql || error "خطا در راه‌اندازی مجدد PostgreSQL"

# ایجاد محیط مجازی پایتون
info "ایجاد محیط مجازی پایتون..."
python3 -m venv $INSTALL_DIR/venv || error "خطا در ایجاد محیط مجازی"
source $INSTALL_DIR/venv/bin/activate || error "خطا در فعال سازی محیط مجازی"

# نصب وابستگی‌های پایتون
info "نصب وابستگی‌های پایتون..."
pip install --upgrade pip || error "خطا در به روزرسانی pip"
pip install sqlalchemy==2.0.28 psycopg2-binary==2.9.9 || error "خطا در نصب وابستگی‌های پایتون"

# ایجاد مدل‌های دیتابیس
info "ایجاد جداول پایگاه داده..."
cat > $TEMP_DIR/create_tables.py <<EOF
import os
import sys
from sqlalchemy import create_engine, MetaData
from sqlalchemy.orm import declarative_base
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.exc import SQLAlchemyError

# خواندن تنظیمات از فایل .env
with open('$INSTALL_DIR/.env') as f:
    for line in f:
        if line.strip() and not line.startswith('#'):
            key, value = line.strip().split('=', 1)
            os.environ[key] = value.strip("'")

try:
    DATABASE_URL = os.getenv('DATABASE_URL')
    engine = create_engine(
        DATABASE_URL,
        connect_args={"connect_timeout": 5},
        pool_pre_ping=True
    )
    Base = declarative_base()

    class User(Base):
        __tablename__ = 'users'
        id = Column(Integer, primary_key=True)
        username = Column(String(50), unique=True)
        password = Column(String(100))
        is_admin = Column(Boolean, default=False)

    class Domain(Base):
        __tablename__ = 'domains'
        id = Column(Integer, primary_key=True)
        name = Column(String(100), unique=True)
        user_id = Column(Integer, ForeignKey('users.id'))

    Base.metadata.create_all(engine)
    print("[SUCCESS] تمام جداول پایگاه داده ساخته شدند!")
except SQLAlchemyError as e:
    print(f"[ERROR] خطا در پایگاه داده: {str(e)}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"[ERROR] خطای غیرمنتظره: {str(e)}", file=sys.stderr)
    sys.exit(1)
EOF

python3 $TEMP_DIR/create_tables.py || error "خطا در ایجاد جداول پایگاه داده"

# تنظیم Nginx و SSL
info "پیکربندی Nginx و SSL..."
mkdir -p /etc/nginx/ssl || error "خطا در ایجاد دایرکتوری SSL"

# ایجاد گواهی SSL خودامضا
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=US/ST=California/L=San Francisco/O=Company/OU=IT/CN=${DOMAIN:-localhost}" 2>/dev/null || error "خطا در ایجاد گواهی SSL"

chmod 600 /etc/nginx/ssl/nginx.key || error "خطا در تنظیم مجوز کلید SSL"

cat > /etc/nginx/sites-available/zhina <<EOF
server {
    listen 80;
    server_name ${DOMAIN:-localhost};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    access_log /var/log/nginx/zhina_access.log;
    error_log /var/log/nginx/zhina_error.log;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN:-localhost};

    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/zhina /etc/nginx/sites-enabled/ || error "خطا در ایجاد لینک نمادین"
rm -f /etc/nginx/sites-enabled/default || info "حذف فایل پیش‌فرض Nginx"
nginx -t || error "تنظیمات Nginx نامعتبر است"
systemctl restart nginx || error "خطا در راه‌اندازی مجدد Nginx"

# نصب و پیکربندی Xray
info "در حال نصب و پیکربندی Xray..."

# دانلود و نصب Xray
XRAY_VERSION="1.8.6"
mkdir -p $XRAY_DIR || error "خطا در ایجاد دایرکتوری Xray"

info "دانلود Xray نسخه $XRAY_VERSION..."
wget -qO $TEMP_DIR/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" || error "خطا در دانلود Xray"

unzip -o $TEMP_DIR/xray.zip -d $XRAY_DIR || error "خطا در اکسترکت فایل Xray"
chmod +x $XRAY_DIR/xray || error "خطا در تنظیم مجوزهای Xray"

# ایجاد سرویس سیستم برای Xray
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=$XRAY_DIR/xray run -config $XRAY_DIR/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# ایجاد فایل پیکربندی Xray با تمام پروتکل‌ها
XRAY_UUID=$(cat /proc/sys/kernel/random/uuid)
SHADOWSOCKS_PASSWORD=$(openssl rand -hex 12)
TROJAN_PASSWORD=$(openssl rand -hex 16)

cat > $XRAY_DIR/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$XRAY_UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/nginx/ssl/nginx.crt",
              "keyFile": "/etc/nginx/ssl/nginx.key"
            }
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$XRAY_UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
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
        "network": "tcp"
      }
    },
    {
      "port": 8989,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-256-gcm",
        "password": "$SHADOWSOCKS_PASSWORD",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

# فعال‌سازی و راه‌اندازی سرویس Xray
systemctl daemon-reload || error "خطا در reload دیمون سیستم"
systemctl enable xray || error "خطا در فعال‌سازی سرویس Xray"
systemctl start xray || error "خطا در راه‌اندازی سرویس Xray"

# باز کردن پورت‌ها در فایروال
info "پیکربندی فایروال..."
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp || info "پورت 80 قبلاً باز است"
    ufw allow 443/tcp || info "پورت 443 قبلاً باز است"
    ufw allow ${PORT}/tcp || info "پورت ${PORT} قبلاً باز است"
    ufw allow 8443/tcp || info "پورت 8443 قبلاً باز است"
    ufw allow 2083/tcp || info "پورت 2083 قبلاً باز است"
    ufw allow 8989/tcp || info "پورت 8989 قبلاً باز است"
    ufw allow 8989/udp || info "پورت 8989/udp قبلاً باز است"
    ufw reload || error "خطا در بارگذاری مجدد فایروال"
fi

# پاکسازی
info "پاکسازی فایل‌های موقت..."
rm -rf $TEMP_DIR || error "خطا در پاکسازی فایل‌های موقت"

success "نصب با موفقیت انجام شد!"
echo -e "\n====== اطلاعات دسترسی پنل ======"
echo "• مسیر نصب: $INSTALL_DIR"
echo "• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}"
echo "• آدرس امن پنل: https://${DOMAIN:-$(curl -s ifconfig.me)}"
echo "• یوزرنیم ادمین: $ADMIN_USERNAME"
echo "• پسورد ادمین: $ADMIN_PASSWORD"
echo "• پسورد دیتابیس: $DB_PASSWORD"

echo -e "\n====== اطلاعات پروتکل‌های Xray ======"
echo "• VLESS:"
echo "  - آدرس: ${DOMAIN:-$(curl -s ifconfig.me)}"
echo "  - پورت: 443"
echo "  - UUID: $XRAY_UUID"
echo "  - Transport: tcp"
echo "  - TLS: true"
echo "  - Flow: xtls-rprx-vision"

echo -e "\n• VMess:"
echo "  - آدرس: ${DOMAIN:-$(curl -s ifconfig.me)}"
echo "  - پورت: 8443"
echo "  - UUID: $XRAY_UUID"
echo "  - AlterId: 0"

echo -e "\n• Trojan:"
echo "  - آدرس: ${DOMAIN:-$(curl -s ifconfig.me)}"
echo "  - پورت: 2083"
echo "  - Password: $TROJAN_PASSWORD"

echo -e "\n• Shadowsocks:"
echo "  - آدرس: ${DOMAIN:-$(curl -s ifconfig.me)}"
echo "  - پورت: 8989"
echo "  - Password: $SHADOWSOCKS_PASSWORD"
echo "  - Method: aes-256-gcm"
echo "============================"
echo "لاگ نصب در $LOG_FILE ذخیره شده است."
