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

# ایجاد فایل config.py جدید
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

# نصب Xray
info "در حال نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install || error "خطا در نصب Xray!"

# ایجاد کانفیگ Xray با تمام پروتکل‌ها
info "در حال ایجاد کانفیگ Xray با تمام پروتکل‌ها..."

# تولید UUID و کلیدهای تصادفی
VMESS_UUID=$(uuidgen)
VLESS_UUID=$(uuidgen)
TROJAN_PASSWORD=$(openssl rand -hex 16)
SHADOWSOCKS_PASSWORD=$(openssl rand -hex 16)
HYSTERIA_OBFS=$(openssl rand -hex 8)
HYSTERIA_AUTH=$(openssl rand -hex 16)

cat <<EOF > /etc/xray/config.json
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        # VMESS
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
        # VLESS
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
        # Trojan
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
        # Shadowsocks
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
        # Hysteria
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
        # gRPC
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

# باز کردن پورت‌ها در فایروال
info "در حال باز کردن پورت‌ها در فایروال..."
PORTS=(443 8443 2083 2095 2097 2098 $PORT)
for port in "${PORTS[@]}"; do
    ufw allow $port/tcp >/dev/null 2>&1
    ufw allow $port/udp >/dev/null 2>&1
    success "پورت $port در فایروال باز شد."
done

# فعال کردن فایروال
ufw --force enable >/dev/null 2>&1
success "فایروال فعال شد."

# نمایش اطلاعات اتصال
success "\n\nتنظیمات Xray با موفقیت انجام شد!"
info "اطلاعات پروتکل‌ها:"
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
echo -e "  Service Name: grpc-service${NC}\n"

# بقیه تنظیمات (دیتابیس، FastAPI و...) مانند قبل
# ...
