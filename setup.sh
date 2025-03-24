#!/bin/bash

# --- رنگ‌ها و توابع ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# --- بررسی root ---
[ "$EUID" -ne 0 ] && error "لطفاً با دسترسی root اجرا کنید."

# --- تولید مقادیر تصادفی ---
generate_uuid() { echo $(cat /proc/sys/kernel/random/uuid); }
generate_password() { echo $(openssl rand -base64 12); }

# --- تنظیمات اولیه ---
DOMAIN=""
IP=$(hostname -I | awk '{print $1}')
WORK_DIR="/var/lib/zhina"
BACKEND_DIR="$WORK_DIR/backend"
XRAY_CONFIG="/etc/xray/config.json"

# --- دریافت اطلاعات کاربر ---
read -p "دامنه (اختیاری): " DOMAIN
read -p "پورت پنل (پیش‌فرض: 8000): " PORT
PORT=${PORT:-8000}

read -p "یوزرنیم ادمین (پیش‌فرض: admin): " ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}

read -sp "پسورد ادمین (Enter برای تولید خودکار): " ADMIN_PASSWORD
[ -z "$ADMIN_PASSWORD" ] && ADMIN_PASSWORD=$(generate_password)
echo ""

# --- ساخت فایل .env ---
cat <<EOF > $BACKEND_DIR/.env
ADMIN_USERNAME="$ADMIN_USERNAME"
ADMIN_PASSWORD="$ADMIN_PASSWORD"
DB_PASSWORD="$(generate_password)"
EOF
chmod 600 $BACKEND_DIR/.env

# --- نصب Xray با تمام پروتکل‌ها ---
info "در حال نصب Xray با تمام پروتکل‌ها..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# --- کانفیگ Xray (تمامی پروتکل‌ها) ---
info "در حال ایجاد کانفیگ کامل Xray..."
cat <<EOF > $XRAY_CONFIG
{
    "log": { "loglevel": "warning" },
    "inbounds": [
        # 1. VMESS (WS + TLS)
        {
            "port": 443,
            "protocol": "vmess",
            "settings": {
                "clients": [ { "id": "$(generate_uuid)", "alterId": 0 } ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "wsSettings": { "path": "/vmess-ws" },
                "tlsSettings": {
                    "certificates": [{
                        "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
                        "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                    }]
                }
            }
        },
        # 2. VLESS (TCP + XTLS)
        {
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [ { "id": "$(generate_uuid)", "flow": "xtls-rprx-vision" } ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "certificates": [{
                        "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
                        "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                    }]
                }
            }
        },
        # 3. Trojan (TCP + TLS)
        {
            "port": 2053,
            "protocol": "trojan",
            "settings": {
                "clients": [ { "password": "$(generate_password)" } ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "certificates": [{
                        "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
                        "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                    }]
                }
            }
        },
        # 4. Shadowsocks 2022
        {
            "port": 2087,
            "protocol": "shadowsocks",
            "settings": {
                "method": "2022-blake3-aes-256-gcm",
                "password": "$(generate_password)",
                "network": "tcp,udp"
            }
        },
        # 5. Hysteria 2
        {
            "port": 2096,
            "protocol": "hysteria",
            "settings": {
                "auth_str": "$(generate_password)",
                "obfs": "$(generate_password)",
                "up_mbps": 100,
                "down_mbps": 100
            }
        },
        # 6. VLESS (gRPC)
        {
            "port": 50051,
            "protocol": "vless",
            "settings": {
                "clients": [ { "id": "$(generate_uuid)" } ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "grpc",
                "grpcSettings": { "serviceName": "grpc-service" },
                "security": "tls",
                "tlsSettings": {
                    "certificates": [{
                        "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
                        "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                    }]
                }
            }
        },
        # 7. VMESS (QUIC)
        {
            "port": 2083,
            "protocol": "vmess",
            "settings": {
                "clients": [ { "id": "$(generate_uuid)", "alterId": 0 } ]
            },
            "streamSettings": {
                "network": "quic",
                "security": "none",
                "quicSettings": {
                    "security": "none",
                    "key": "",
                    "header": { "type": "none" }
                }
            }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "tag": "direct" },
        { "protocol": "blackhole", "tag": "blocked" }
    ]
}
EOF

# --- راه‌اندازی سرویس‌ها ---
systemctl enable --now xray
success "Xray با موفقیت راه‌اندازی شد!"

# --- نمایش اطلاعات ---
echo -e "\n${GREEN}=== تنظیمات پروتکل‌ها ===${NC}"
echo -e "1. VMESS (WS+TLS): پورت 443"
echo -e "2. VLESS (XTLS): پورت 8443"
echo -e "3. Trojan: پورت 2053"
echo -e "4. Shadowsocks 2022: پورت 2087"
echo -e "5. Hysteria 2: پورت 2096"
echo -e "6. VLESS (gRPC): پورت 50051"
echo -e "7. VMESS (QUIC): پورت 2083"
echo -e "\n${GREEN}اطلاعات ورود به پنل:${NC}"
echo -e "یوزرنیم: $ADMIN_USERNAME"
echo -e "پسورد: $ADMIN_PASSWORD"
