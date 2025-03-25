#!/bin/bash
set -euo pipefail

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/var/lib/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
PANEL_DOMAIN="panel.yourdomain.com"  # تغییر به دامنه واقعی شما
PANEL_PORT=8001
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -hex 8)
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
APP_ENTRYPOINT="$INSTALL_DIR/backend/app.py"
CB_DIR="$INSTALL_DIR/backend/xray_config"

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ------------------- توابع جدید برای مدیریت تداخل پورت -------------------
configure_nginx_sni() {
    info "تنظیم Nginx برای SNI-based分流"
    
    # ایجاد کانفیگ Nginx
    cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;

stream {
    map \$ssl_preread_server_name \$backend {
        ${PANEL_DOMAIN} 127.0.0.1:${PANEL_PORT};
        default 127.0.0.1:443_xray;
    }

    server {
        listen 443 reuseport;
        listen [::]:443 reuseport;
        ssl_preread on;
        proxy_pass \$backend;
    }
}

http {
    server {
        listen 80;
        server_name ${PANEL_DOMAIN};
        return 301 https://\$host\$request_uri;
    }
}
EOF

    systemctl restart nginx
    success "Nginx با موفقیت برای SNI تنظیم شد!"
}

modify_xray_for_sni() {
    info "به‌روزرسانی Xray برای کار با SNI"
    
    # تغییر پورت Xray به پورت داخلی
    sed -i 's/"port": 443/"port": 443_xray/g' "$XRAY_CONFIG"
    
    # اضافه کردن دامنه پنل به serverNames
    sed -i '/"serverNames": \["www.amazon.com"/s/"/"'"${PANEL_DOMAIN}"', "/' "$XRAY_CONFIG"
    
    systemctl restart xray
    success "Xray برای کار با SNI به‌روزرسانی شد!"
}

setup_panel_ssl() {
    info "تنظیم SSL برای پنل مدیریتی"
    
    apt-get install -y certbot python3-certbot-nginx
    certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}
    echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
    
    success "SSL برای پنل تنظیم شد!"
}

# ------------------- توابع اصلی (بدون تغییر) -------------------
install_prerequisites() {
    info "نصب پیش‌نیازهای سیستم..."
    apt-get update
    apt-get install -y git python3 python3-venv python3-pip postgresql nginx curl wget openssl unzip uuid-runtime
    success "پیش‌نیازها با موفقیت نصب شدند!"
}

setup_database() {
    info "تنظیم پایگاه داده..."
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$(openssl rand -hex 16)';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
EOF
    sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
    success "پایگاه داده با موفقیت تنظیم شد!"
}

setup_requirements() {
    info "ایجاد فایل requirements.txt..."
    cat > "$INSTALL_DIR/requirements.txt" <<EOF
sqlalchemy==2.0.28
psycopg2-binary==2.9.9
fastapi==0.103.2
uvicorn==0.23.2
python-multipart==0.0.6
jinja2==3.1.2
python-dotenv==1.0.0
EOF
    success "فایل requirements.txt ایجاد شد!"

    info "نصب وابستگی‌های مورد نیاز..."
    python3 -m venv $INSTALL_DIR/venv
    source $INSTALL_DIR/venv/bin/activate
    pip install -U pip setuptools wheel
    pip install -r "$INSTALL_DIR/requirements.txt"
    deactivate
    success "وابستگی‌ها با موفقیت نصب شدند!"
}

install_xray() {
    info "نصب و پیکربندی Xray..."
    
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"
    
    mkdir -p "$XRAY_DIR"
    wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip
    unzip -o /tmp/xray.zip -d "$XRAY_DIR"
    chmod +x "$XRAY_EXECUTABLE"

    XRAY_UUID=$(uuidgen)
    XRAY_PATH="/$(openssl rand -hex 6)"
    HTTP_PATH="/$(openssl rand -hex 4)"
    
    REALITY_KEYS=$($XRAY_EXECUTABLE x25519)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)

    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {"loglevel": "warning"},
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": "$XRAY_UUID"}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "www.amazon.com:443",
                    "xver": 0,
                    "serverNames": ["www.amazon.com"],
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "shortIds": ["$REALITY_SHORT_ID"]
                }
            }
        },
        {
            "port": 8080,
            "protocol": "vmess",
            "settings": {
                "clients": [{"id": "$XRAY_UUID"}]
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "path": "$XRAY_PATH",
                    "headers": {}
                }
            }
        },
        {
            "port": 8443,
            "protocol": "trojan",
            "settings": {
                "clients": [{"password": "$XRAY_UUID"}]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h2", "http/1.1"],
                    "certificates": [{
                        "certificateFile": "/etc/nginx/ssl/fullchain.pem",
                        "keyFile": "/etc/nginx/ssl/privkey.pem"
                    }]
                }
            }
        },
        {
            "port": 8388,
            "protocol": "shadowsocks",
            "settings": {
                "method": "aes-256-gcm",
                "password": "$XRAY_UUID",
                "network": "tcp,udp"
            }
        },
        {
            "port": 8081,
            "protocol": "http",
            "settings": {
                "timeout": 300,
                "allowTransparent": false
            },
            "streamSettings": {
                "network": "tcp"
            }
        },
        {
            "port": 8082,
            "protocol": "http",
            "settings": {
                "timeout": 300,
                "allowTransparent": false
            },
            "streamSettings": {
                "network": "h2",
                "httpSettings": {
                    "path": "$HTTP_PATH",
                    "host": ["www.example.com"]
                }
            }
        }
    ],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
    success "Xray با موفقیت نصب و پیکربندی شد!"
}

setup_ssl() {
    info "تنظیم گواهی SSL..."
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/privkey.pem \
        -out /etc/nginx/ssl/fullchain.pem \
        -subj "/CN=$(curl -s ifconfig.me)"
    chmod 600 /etc/nginx/ssl/*
    success "گواهی SSL با موفقیت ایجاد شد!"
}

create_tables() {
    info "ایجاد جداول دیتابیس..."
    sudo -u postgres psql -d $DB_NAME <<EOF
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(255) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
        traffic_limit BIGINT DEFAULT 0,
        usage_duration INT DEFAULT 0,
        simultaneous_connections INT DEFAULT 1,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS domains (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL,
        description JSONB,
        owner_id INT REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS subscriptions (
        id SERIAL PRIMARY KEY,
        uuid UUID UNIQUE DEFAULT uuid_generate_v4(),
        data_limit BIGINT DEFAULT 0,
        expiry_date TIMESTAMP,
        max_connections INT DEFAULT 1,
        user_id INT REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS settings (
        id SERIAL PRIMARY KEY,
        language VARCHAR(10) DEFAULT 'fa',
        theme VARCHAR(20) DEFAULT 'dark',
        enable_notifications BOOLEAN DEFAULT true,
        preferences JSONB,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS nodes (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL,
        ip_address VARCHAR(45) NOT NULL,
        port INT NOT NULL,
        protocol VARCHAR(20) NOT NULL,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    INSERT INTO users (username, password, is_active) 
    VALUES ('$ADMIN_USER', crypt('$ADMIN_PASS', gen_salt('bf')), true);
EOF
    success "جداول دیتابیس با موفقیت ایجاد شدند!"
}

setup_services() {
    info "تنظیم سرویس‌های سیستم..."

    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$XRAY_DIR
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=always
RestartSec=3
LimitNOFILE=65535
Environment="XRAY_LOCATION_ASSET=$XRAY_DIR"

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/backend
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port $PANEL_PORT --workers $UVICORN_WORKERS
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray zhina-panel
    systemctl start xray zhina-panel
    success "سرویس‌ها با موفقیت تنظیم و راه‌اندازی شدند!"
}

show_info() {
    PUBLIC_IP=$(curl -s ifconfig.me)
    success "\n\n=== نصب کامل شد! ==="
    echo -e "دسترسی پنل مدیریتی:"
    echo -e "• آدرس: ${GREEN}https://${PANEL_DOMAIN}${NC}"
    echo -e "• یوزرنیم ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "• پسورد ادمین: ${YELLOW}${ADMIN_PASS}${NC}"

    echo -e "\nتنظیمات Xray:"
    echo -e "• پروتکل‌های فعال:"
    echo -e "  - ${YELLOW}VLESS + Reality${NC} (پورت 443 با SNI)"
    echo -e "  - ${YELLOW}VMess + WS${NC} (پورت 8080 - مسیر: ${XRAY_PATH})"
    echo -e "  - ${YELLOW}Trojan${NC} (پورت 8443)"
    echo -e "  - ${YELLOW}Shadowsocks${NC} (پورت 8388)"
    echo -e "• UUID/پسورد مشترک: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• کلید عمومی Reality: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"

    echo -e "\nدستورات مدیریت:"
    echo -e "• وضعیت سرویس‌ها: ${YELLOW}systemctl status {xray,zhina-panel,nginx}${NC}"
    echo -e "• مشاهده لاگ‌ها: ${YELLOW}journalctl -u xray -u zhina-panel -f${NC}"
}

# ------------------- اجرای اصلی -------------------
main() {
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد!"

    # 1. نصب پیش‌نیازها
    install_prerequisites

    # 2. ایجاد کاربر سرویس
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d $INSTALL_DIR $SERVICE_USER
    fi

    # 3. تنظیم دیتابیس
    setup_database

    # 4. دریافت کدهای برنامه
    info "دریافت کدهای برنامه..."
    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR"
        git pull || error "خطا در بروزرسانی کدها"
    else
        rm -rf "$INSTALL_DIR"
        git clone https://github.com/naseh42/zhina.git "$INSTALL_DIR" || error "خطا در دریافت کدها"
    fi
    chown -R $SERVICE_USER:$SERVICE_USER $INSTALL_DIR
    success "کدهای برنامه با موفقیت دریافت شدند!"

    # 5. نصب وابستگی‌ها
    setup_requirements

    # 6. تنظیم SSL
    setup_ssl

    # 7. نصب Xray
    install_xray

    # 8. تنظیم Nginx و SNI
    configure_nginx_sni
    modify_xray_for_sni
    setup_panel_ssl

    # 9. ایجاد جداول
    create_tables

    # 10. تنظیم سرویس‌ها
    setup_services

    # 11. نمایش اطلاعات
    show_info
}

main
