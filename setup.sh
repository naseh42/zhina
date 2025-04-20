#!/bin/bash
set -euo pipefail
exec > >(tee -a "/var/log/zhina-install.log") 2>&1

# ------------------- تنظیمات اصلی -------------------
INSTALL_DIR="/opt/zhina"
BACKEND_DIR="$INSTALL_DIR/backend"
FRONTEND_DIR="$INSTALL_DIR/frontend"
CONFIG_DIR="/etc/zhina"
LOG_DIR="/var/log/zhina"
XRAY_DIR="/usr/local/bin/xray"
XRAY_EXECUTABLE="$XRAY_DIR/xray"
XRAY_CONFIG="/etc/xray/config.json"
SERVICE_USER="zhina"
DB_NAME="zhina_db"
DB_USER="zhina_user"
PANEL_PORT=8001
ADMIN_USER="admin"
ADMIN_EMAIL=""
ADMIN_PASS=""
XRAY_VERSION="1.8.11"
UVICORN_WORKERS=4
XRAY_HTTP_PORT=2083
DB_PASSWORD=$(openssl rand -hex 16)
XRAY_PATH="/$(openssl rand -hex 8)"
SECRETS_DIR="/etc/zhina/secrets"
DEFAULT_THEME="dark"
DEFAULT_LANGUAGE="fa"
PANEL_DOMAIN=""
GITHUB_REPO="naseh42/zhina"
REALITY_DEST=""
REALITY_SERVER_NAMES=""
SSL_CERT=""
SSL_KEY=""

# ------------------- رنگ‌ها و توابع -------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { 
    echo -e "${RED}[✗] $1${NC}" >&2
    echo -e "برای مشاهده خطاهای کامل، فایل لاگ را بررسی کنید: ${YELLOW}/var/log/zhina-install.log${NC}"
    exit 1
}
success() { echo -e "${GREEN}[✓] $1${NC}"; }
info() { echo -e "${BLUE}[i] $1${NC}"; }
warning() { echo -e "${YELLOW}[!] $1${NC}"; }

# ------------------- توابع کمکی -------------------
disable_ipv6() {
    info "غیرفعال کردن موقت IPv6..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
}

fix_nginx() {
    info "رفع مشکلات Nginx..."
    systemctl stop nginx 2>/dev/null || true
    
    for port in 80 443 $XRAY_HTTP_PORT 8443; do
        if ss -tuln | grep -q ":$port "; then
            pid=$(ss -tulnp | grep ":$port " | awk '{print $7}' | cut -d= -f2 | cut -d, -f1)
            kill -9 $pid 2>/dev/null || warning "نمی‌توان پورت $port را آزاد کرد"
        fi
    done
    
    sed -i 's/listen \[::\]:80/# listen [::]:80/g' /etc/nginx/sites-enabled/*
    sed -i 's/listen \[::\]:443/# listen [::]:443/g' /etc/nginx/sites-enabled/*
    
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    
    apt-get install -y -f || error "خطا در رفع وابستگی‌ها"
    dpkg --configure -a || error "خطا در پیکربندی بسته‌ها"
}

# ------------------- تابع ایجاد منو -------------------
create_management_menu() {
    local menu_file="/usr/local/bin/zhina-manager"
    
    cat > "$menu_file" <<'EOF'
#!/bin/bash
set -euo pipefail

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# تنظیمات اصلی
INSTALL_DIR="/opt/zhina"
CONFIG_DIR="/etc/zhina"
LOG_DIR="/var/log/zhina"
PANEL_PORT=$(grep "PANEL_PORT" $INSTALL_DIR/backend/.env | cut -d= -f2)
PANEL_DOMAIN=$(grep "PANEL_DOMAIN" $INSTALL_DIR/backend/.env | cut -d= -f2)
ADMIN_USER=$(grep "ADMIN_USERNAME" $INSTALL_DIR/backend/.env | cut -d= -f2)
ADMIN_EMAIL=$(grep "ADMIN_EMAIL" $INSTALL_DIR/backend/.env | cut -d= -f2)
ADMIN_PASS=$(grep "ADMIN_PASSWORD" $INSTALL_DIR/backend/.env | cut -d= -f2)
XRAY_PATH=$(grep "XRAY_PATH" $INSTALL_DIR/backend/.env | cut -d= -f2)
XRAY_HTTP_PORT=$(grep "XRAY_HTTP_PORT" $INSTALL_DIR/backend/.env | cut -d= -f2)

show_credentials() {
    echo -e "${GREEN}=== اطلاعات دسترسی پنل ===${NC}"
    echo -e "آدرس پنل: ${YELLOW}https://${PANEL_DOMAIN}${NC}"
    echo -e "نام کاربری ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "رمز عبور ادمین: ${YELLOW}${ADMIN_PASS}${NC}"
    echo -e "ایمیل ادمین: ${YELLOW}${ADMIN_EMAIL}${NC}"
    echo -e "مسیر WS: ${YELLOW}${XRAY_PATH}${NC}"
    echo -e "پورت WS: ${YELLOW}${XRAY_HTTP_PORT}${NC}"
}

restart_services() {
    echo -e "${BLUE}راه‌اندازی مجدد سرویس‌ها...${NC}"
    systemctl restart xray nginx zhina-panel postgresql
    echo -e "${GREEN}سرویس‌ها با موفقیت راه‌اندازی مجدد شدند.${NC}"
}

check_services() {
    echo -e "${BLUE}=== بررسی وضعیت سرویس‌ها ===${NC}"
    
    DB_CHECK=$(sudo -u postgres psql -d zhina_db -tAc "SELECT COUNT(*) FROM inbounds" 2>/dev/null || echo "0")
    XRAY_CHECK=$(curl -s http://localhost:${PANEL_PORT}/api/v1/xray/config | jq -r '.status' 2>/dev/null || echo "error")
    
    echo -e "• وضعیت Xray: $(systemctl is-active xray)"
    echo -e "• وضعیت دیتابیس: $(systemctl is-active postgresql)"
    echo -e "• تعداد تنظیمات در دیتابیس: ${DB_CHECK}"
    
    if [[ "$XRAY_CHECK" == "success" && "$DB_CHECK" -gt 0 ]]; then
        echo -e "${GREEN}✓ ارتباط Xray و دیتابیس به درستی کار می‌کند${NC}"
    else
        echo -e "${RED}✗ مشکل در ارتباط بین Xray و دیتابیس${NC}"
        journalctl -u xray -n 20 --no-pager | grep -i database
    fi
}

update_panel() {
    echo -e "${BLUE}دریافت آخرین نسخه پنل...${NC}"
    cd $INSTALL_DIR
    git pull origin main || { echo -e "${RED}خطا در دریافت آپدیت‌ها${NC}"; return 1; }
    
    source $INSTALL_DIR/venv/bin/activate
    pip install -r $INSTALL_DIR/backend/requirements.txt || { echo -e "${RED}خطا در نصب نیازمندی‌ها${NC}"; return 1; }
    deactivate
    
    systemctl restart zhina-panel
    echo -e "${GREEN}پنل با موفقیت به آخرین نسخه آپدیت شد.${NC}"
}

reinstall_panel() {
    read -p "آیا مطمئنید می‌خواهید پنل را مجدداً نصب کنید؟ (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}شروع نصب مجدد...${NC}"
        bash <(curl -sL https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh)
    fi
}

show_logs() {
    echo -e "${GREEN}=== لاگ‌های سیستم ===${NC}"
    echo "1. لاگ پنل (خطاها)"
    echo "2. لاگ پنل (دسترسی)"
    echo "3. لاگ Xray"
    echo "4. لاگ Nginx"
    echo "5. لاگ دیتابیس"
    echo "0. بازگشت"
    
    read -p "انتخاب کنید: " log_choice
    case $log_choice in
        1) tail -f $LOG_DIR/panel/error.log ;;
        2) tail -f $LOG_DIR/panel/access.log ;;
        3) journalctl -u xray -f ;;
        4) tail -f /var/log/nginx/access.log ;;
        5) tail -f /var/log/postgresql/postgresql-*.log ;;
        0) return ;;
        *) echo -e "${RED}انتخاب نامعتبر!${NC}" ;;
    esac
}

while true; do
    clear
    echo -e "${GREEN}=== منوی مدیریت Zhina ===${NC}"
    echo "1. نمایش اطلاعات دسترسی"
    echo "2. راه‌اندازی مجدد سرویس‌ها"
    echo "3. بررسی وضعیت سرویس‌ها"
    echo "4. آپدیت پنل به آخرین نسخه"
    echo "5. نصب مجدد پنل"
    echo "6. مشاهده لاگ‌ها"
    echo "0. خروج"
    
    read -p "لطفاً عدد مورد نظر را انتخاب کنید: " choice
    case $choice in
        1) show_credentials ;;
        2) restart_services ;;
        3) check_services ;;
        4) update_panel ;;
        5) reinstall_panel ;;
        6) show_logs ;;
        0) exit 0 ;;
        *) echo -e "${RED}انتخاب نامعتبر!${NC}" ;;
    esac
    
    read -p "برای ادامه Enter بزنید..." -n 1 -r
done
EOF

    chmod +x "$menu_file"
    success "منوی مدیریت ایجاد شد. با دستور ${YELLOW}zhina-manager${NC} می‌توانید آن را اجرا کنید."
}

# ------------------- دریافت اطلاعات ادمین -------------------
get_admin_credentials() {
    while [[ -z "$ADMIN_EMAIL" ]]; do
        read -p "لطفا ایمیل ادمین را وارد کنید: " ADMIN_EMAIL
        if [[ -z "$ADMIN_EMAIL" ]]; then
            echo -e "${RED}ایمیل ادمین نمی‌تواند خالی باشد!${NC}"
        elif [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            echo -e "${RED}فرمت ایمیل نامعتبر است!${NC}"
            ADMIN_EMAIL=""
        fi
    done

    while [[ -z "$ADMIN_PASS" ]]; do
        read -sp "لطفا رمز عبور ادمین را وارد کنید (حداقل 8 کاراکتر): " ADMIN_PASS
        echo
        if [[ ${#ADMIN_PASS} -lt 8 ]]; then
            echo -e "${RED}رمز عبور باید حداقل 8 کاراکتر باشد!${NC}"
            ADMIN_PASS=""
        fi
    done
}

# ------------------- بررسی سیستم -------------------
check_system() {
    info "بررسی پیش‌نیازهای سیستم..."
    
    [[ $EUID -ne 0 ]] && error "این اسکریپت نیاز به دسترسی root دارد"
    
    if [[ ! -f /etc/os-release ]]; then
        error "سیستم عامل نامشخص"
    fi
    source /etc/os-release
    [[ "$ID" != "ubuntu" && "$ID" != "debian" ]] && 
        warning "این اسکریپت فقط بر روی Ubuntu/Debian تست شده است"
    
    if ! python3 -c "import sys; exit(1) if sys.version_info < (3, 8) else exit(0)"; then
        error "نیاز به پایتون نسخه 3.8 یا بالاتر دارید"
    fi
    
    local free_space=$(df --output=avail -B 1G / | tail -n 1 | tr -d ' ')
    if [[ $free_space -lt 5 ]]; then
        warning "فضای دیسک کم است (کمتر از 5GB فضای آزاد)"
    fi
    
    for cmd in curl wget git python3; do
        if ! command -v $cmd &> /dev/null; then
            error "دستور $cmd یافت نشد!"
        fi
    done
    
    success "بررسی سیستم کامل شد"
}

# ------------------- نصب پیش‌نیازها -------------------
install_prerequisites() {
    info "نصب بسته‌های ضروری..."
    
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    
    apt-get update -y || error "خطا در بروزرسانی لیست پکیج‌ها"
    
    for pkg in git python3 python3-venv python3-pip postgresql postgresql-contrib curl wget openssl unzip uuid-runtime build-essential python3-dev libpq-dev jq; do
        apt-get install -y $pkg || warning "خطا در نصب $pkg - ادامه فرآیند نصب..."
    done
    
    apt-get install -y certbot python3-certbot || warning "خطا در نصب certbot"
    
    info "نصب Nginx..."
    disable_ipv6
    if ! apt-get install -y nginx; then
        warning "خطا در نصب Nginx، تلاش برای رفع..."
        fix_nginx
        apt-get install -y nginx || error "خطا در نصب Nginx پس از رفع مشکل"
    fi
    
    apt-get install -y -f || warning "خطا در رفع مشکلات باقیمانده بسته‌ها"
    
    success "پیش‌نیازها با موفقیت نصب شدند"
}

# ------------------- تنظیم کاربر و دایرکتوری‌ها -------------------
setup_environment() {
    info "تنظیم محیط سیستم..."
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER" || 
            error "خطا در ایجاد کاربر $SERVICE_USER"
    fi
    
    mkdir -p \
        "$BACKEND_DIR" \
        "$FRONTEND_DIR" \
        "$CONFIG_DIR" \
        "$LOG_DIR/panel" \
        "$XRAY_DIR" \
        "$SECRETS_DIR" \
        "/etc/xray" || error "خطا در ایجاد دایرکتوری‌ها"
    
    chown -R "$SERVICE_USER":"$SERVICE_USER" \
        "$INSTALL_DIR" \
        "$BACKEND_DIR" \
        "$LOG_DIR" \
        "$SECRETS_DIR" \
        "$CONFIG_DIR"

    touch "$LOG_DIR/panel/access.log" "$LOG_DIR/panel/error.log"
    chown "$SERVICE_USER":"$SERVICE_USER" "$LOG_DIR/panel"/*.log
    
    if [ -d "./backend" ]; then
        cp -r "./backend"/* "$BACKEND_DIR"/ || error "خطا در انتقال بک‌اند"
    else
        error "پوشه backend در مسیر جاری یافت نشد!"
    fi
    
    if [ -d "./frontend" ]; then
        cp -r "./frontend"/* "$FRONTEND_DIR"/ || error "خطا در انتقال فرانت‌اند"
    else
        error "پوشه frontend در مسیر جاری یافت نشد!"
    fi
    
    find "$BACKEND_DIR" -type d -exec chmod 750 {} \;
    find "$BACKEND_DIR" -type f -exec chmod 640 {} \;

    chown -R "$SERVICE_USER":"$SERVICE_USER" "$BACKEND_DIR"

    find "$FRONTEND_DIR" -type d -exec chmod 755 {} \;
    find "$FRONTEND_DIR" -type f -exec chmod 644 {} \;

    success "محیط سیستم با موفقیت تنظیم شد"
}

# ------------------- تنظیم دیتابیس -------------------
setup_database() {
    info "تنظیم پایگاه داده PostgreSQL..."
    
    systemctl start postgresql || error "خطا در راه‌اندازی PostgreSQL"
    
    sudo -u postgres psql <<EOF || error "خطا در اجرای دستورات PostgreSQL"
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP USER IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    CREATE DATABASE $DB_NAME OWNER $DB_USER;
    \c $DB_NAME
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF

    sudo -u postgres psql -c "
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
    " || error "خطا در اعطای دسترسی‌های دیتابیس"
    
    local pg_conf="/etc/postgresql/$(ls /etc/postgresql | head -1)/main/postgresql.conf"
    if [ -f "$pg_conf" ]; then
        sed -i '/^#listen_addresses/s/^#//; s/localhost/*/' "$pg_conf"
        echo "host $DB_NAME $DB_USER 127.0.0.1/32 scram-sha-256" >> /etc/postgresql/*/main/pg_hba.conf
    else
        warning "فایل پیکربندی PostgreSQL یافت نشد!"
    fi
    
    systemctl restart postgresql || error "خطا در راه‌اندازی مجدد PostgreSQL"
    
    sudo -u postgres psql -d "$DB_NAME" <<EOF || error "خطا در ایجاد جداول دیتابیس"
    CREATE TABLE IF NOT EXISTS inbounds (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        settings JSONB NOT NULL,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    INSERT INTO inbounds (name, settings) VALUES 
    ('default_vless', '{"port": 443, "protocol": "vless"}'),
    ('default_vmess', '{"port": $XRAY_HTTP_PORT, "protocol": "vmess", "path": "$XRAY_PATH"}')
    ON CONFLICT DO NOTHING;

    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(100) UNIQUE,
        hashed_password VARCHAR(255) NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        is_admin BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
    );

    INSERT INTO users (username, email, hashed_password, is_active, is_admin)
    VALUES ('$ADMIN_USER', '$ADMIN_EMAIL', crypt('$ADMIN_PASS', gen_salt('bf')), TRUE, TRUE)
    ON CONFLICT (username) DO NOTHING;
EOF
    
    success "پایگاه داده با موفقیت تنظیم شد"
}

# ------------------- تنظیم محیط پایتون -------------------
setup_python() {
    info "تنظیم محیط پایتون..."
    
    python3 -m venv "$INSTALL_DIR/venv" || error "خطا در ایجاد محیط مجازی"
    source "$INSTALL_DIR/venv/bin/activate"
    
    pip install --upgrade pip wheel || error "خطا در بروزرسانی pip و wheel"
    
    if [ -f "$BACKEND_DIR/requirements.txt" ]; then
        pip install -r "$BACKEND_DIR/requirements.txt" || error "خطا در نصب نیازمندی‌های پایتون"
    else
        pip install \
            fastapi==0.103.0 \
            pydantic==2.0.3 \
            pydantic-settings \
            email-validator==2.2.0 \
            dnspython==2.7.0 \
            idna==3.10 \
            qrcode[pil]==7.3 \
            jinja2 \
            python-multipart \
            uvicorn==0.23.2 \
            psycopg2-binary==2.9.7 \
            python-jose==3.3.0 \
            sqlalchemy==2.0.28 \
            python-dotenv==1.0.0 \
            passlib==1.7.4 \
            cryptography==41.0.7 \
            psutil==5.9.5 \
            httpx==0.25.2 \
            python-dateutil==2.8.2 \
            pyotp==2.9.0 \
            jq \
            || error "خطا در نصب نیازمندی‌های پایتون"
    fi
    
    deactivate
    
    chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/venv"
    chmod 750 "$INSTALL_DIR/venv/bin/uvicorn" 2>/dev/null || true
    
    success "محیط پایتون تنظیم شد"
}

# ------------------- نصب Xray با تمام پروتکل‌ها -------------------

    setup_xray() {
    info "نصب و پیکربندی Xray با تمام پروتکل‌ها..."
    systemctl stop xray 2>/dev/null || true

    # تنظیم مسیر صحیح SSL
    SSL_CERT="/etc/nginx/ssl/fullchain.pem"
    SSL_KEY="/etc/nginx/ssl/privkey.pem"

    # بررسی وجود فایل‌های SSL
    if [[ ! -f "$SSL_CERT" || ! -f "$SSL_KEY" ]]; then
        error "فایل‌های SSL یافت نشدند: $SSL_CERT یا $SSL_KEY"
        return 1
    fi

    # تولید کلیدهای Reality
    REALITY_KEYS=$("$XRAY_EXECUTABLE" x25519)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 4)
    XRAY_UUID=$(uuidgen)
    TROJAN_PASSWORD=$(openssl rand -hex 16)
    SHADOWSOCKS_PASSWORD=$(openssl rand -hex 16)
    SOCKS_USERNAME="zhina-user"
    SOCKS_PASSWORD=$(openssl rand -hex 8)

    # تنظیمات هوشمند Reality بر اساس دامنه/آیپی
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        REALITY_DEST="$PANEL_DOMAIN:443"
        REALITY_SERVER_NAMES="[\"$PANEL_DOMAIN\"]"
        warning "تنظیم Reality برای استفاده مستقیم با IP"
    else
        REALITY_DEST="www.datadoghq.com:443"
        REALITY_SERVER_NAMES='["www.datadoghq.com","www.lovelace.com"]'
    fi

    # تنظیمات Xray
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning",
        "access": "$LOG_DIR/xray-access.log",
        "error": "$LOG_DIR/xray-error.log"
    },
    "api": {
        "tag": "api",
        "services": ["StatsService", "HandlerService", "LoggerService"]
    },
    "stats": {},
    "policy": {
        "levels": {
            "0": {
                "statsUserUplink": true,
                "statsUserDownlink": true
            }
        }
    },
    "inbounds": [
        {
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$XRAY_UUID",
                        "flow": "xtls-rprx-vision",
                        "email": "user@reality"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$REALITY_DEST",
                    "xver": 0,
                    "serverNames": $REALITY_SERVER_NAMES,
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "shortIds": ["$REALITY_SHORT_ID"],
                    "fingerprint": "chrome"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        },
        {
            "port": 8444,
            "protocol": "trojan",
            "settings": {
                "clients": [
                    {
                        "password": "$TROJAN_PASSWORD",
                        "email": "user@trojan"
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "serverName": "$PANEL_DOMAIN",
                    "certificates": [
                        {
                            "certificateFile": "$SSL_CERT",
                            "keyFile": "$SSL_KEY"
                        }
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct",
            "settings": {
                "domainStrategy": "UseIP"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "blocked",
            "settings": {}
        },
        {
            "protocol": "dns",
            "tag": "dns-out"
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "blocked"
            },
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "blocked"
            }
        ]
    }
}
EOF

    # تنظیم مالکیت و دسترسی
    chown "$SERVICE_USER":"$SERVICE_USER" "$XRAY_CONFIG"
    chmod 640 "$XRAY_CONFIG"

    # ایجاد سرویس Xray
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target postgresql.service
[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray || error "خطا در راه‌اندازی Xray"
    sleep 2
    if ! systemctl is-active --quiet xray; then
        journalctl -u xray -n 30 --no-pager
        error "سرویس Xray فعال نشد. لاگ‌ها را بررسی کنید."
    fi
    success "Xray با تمام پروتکل‌ها پیکربندی شد"
}

# ------------------- تنظیم Nginx -------------------
setup_nginx() {
    info "تنظیم Nginx..."
    
    systemctl stop nginx 2>/dev/null || true
    
    for port in 80 443; do
        if ss -tuln | grep -q ":$port "; then
            pid=$(ss -tulnp | grep ":$port " | awk '{print $7}' | cut -d= -f2 | cut -d, -f1)
            kill -9 $pid 2>/dev/null || warning "نمی‌توان پورت $port را آزاد کرد"
        fi
    done
    
    if grep -q 'nginx: \[emerg\] socket() \[::\]:80 failed' /var/log/nginx/error.log 2>/dev/null; then
        disable_ipv6
        sed -i 's/listen \[::\]:80/# listen [::]:80/g' /etc/nginx/sites-enabled/*
        sed -i 's/listen \[::\]:443/# listen [::]:443/g' /etc/nginx/sites-enabled/*
    fi
    
    read -p "آیا از دامنه اختصاصی استفاده می‌کنید؟ (y/n) " use_domain
    if [[ "$use_domain" =~ ^[Yy]$ ]]; then
        while [[ -z "$PANEL_DOMAIN" ]]; do
            read -p "نام دامنه خود را وارد کنید (مثال: example.com): " PANEL_DOMAIN
            [[ -z "$PANEL_DOMAIN" ]] && echo -e "${RED}نام دامنه نمی‌تواند خالی باشد!${NC}"
        done
    else
        PANEL_DOMAIN="$(curl -s ifconfig.me)"
        echo -e "${YELLOW}از آدرس IP عمومی استفاده می‌شود: ${PANEL_DOMAIN}${NC}"
    fi

    cat > /etc/nginx/conf.d/zhina.conf <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    
    root $FRONTEND_DIR;
    
    location /api {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        
        add_header 'Access-Control-Allow-Origin' '\$http_origin' always;
        add_header 'Access-Control-Allow-Credentials' 'true' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
    
    location /ws {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_connect_timeout 5s;
    }
    
    location /template/ {
        alias $FRONTEND_DIR/template/;
        try_files \$uri /login.html /dashboard.html /settings.html /users.html /base.html =404;
    }
    
    location /style/css/ {
        alias $FRONTEND_DIR/style/css/;
    }

    location $XRAY_PATH {
        proxy_pass http://127.0.0.1:$XRAY_HTTP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location ~* \.env$ {
        deny all;
        return 404;
    }

    location ~* \.(bak|git|htaccess|htpasswd|swp|swx)$ {
        deny all;
        return 404;
    }
}
EOF

    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    
    nginx -t || error "خطا در پیکربندی Nginx"
    
    systemctl restart nginx || error "خطا در راه‌اندازی Nginx"
    
    success "Nginx با موفقیت پیکربندی شد"
}

# ------------------- تنظیم SSL -------------------
setup_ssl() {
    info "تنظیم گواهی SSL..."
    
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        mkdir -p /etc/nginx/ssl
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/privkey.pem \
            -out /etc/nginx/ssl/fullchain.pem \
            -subj "/CN=$PANEL_DOMAIN"
        ssl_type="self-signed"
        
        # تنظیم مالکیت و سطح دسترسی فایل‌های SSL
        chown root:root /etc/nginx/ssl/fullchain.pem /etc/nginx/ssl/privkey.pem
        chmod 644 /etc/nginx/ssl/fullchain.pem
        chmod 600 /etc/nginx/ssl/privkey.pem
        
        cat >> /etc/nginx/conf.d/zhina.conf <<EOF

server {
    listen 443 ssl;
    server_name $PANEL_DOMAIN;
    
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location $XRAY_PATH {
        proxy_pass http://127.0.0.1:$XRAY_HTTP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
    else
        if certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.} || \
           certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email admin@${PANEL_DOMAIN#*.}; then
            ssl_type="letsencrypt"
            echo "0 12 * * * root certbot renew --quiet" >> /etc/crontab
        else
            warning "خطا در دریافت گواهی Let's Encrypt، از گواهی خودامضا استفاده می‌شود"
            setup_ssl
            return
        fi
    fi
    
    systemctl restart nginx || error "خطا در راه‌اندازی مجدد Nginx"
    
    success "SSL تنظیم شد (نوع: $ssl_type)"
}

# ------------------- تنظیم فایل محیط -------------------
setup_env() {
    info "تنظیم فایل محیط..."
    
    cat > "$BACKEND_DIR/.env" <<EOF
# تنظیمات دیتابیس
DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@localhost/$DB_NAME

# تنظیمات Xray
REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
XRAY_UUID=$XRAY_UUID
XRAY_PATH=$XRAY_PATH
XRAY_HTTP_PORT=$XRAY_HTTP_PORT
TROJAN_PASSWORD=$TROJAN_PASSWORD
SHADOWSOCKS_PASSWORD=$SHADOWSOCKS_PASSWORD
SOCKS_USERNAME=$SOCKS_USERNAME
SOCKS_PASSWORD=$SOCKS_PASSWORD

# تنظیمات امنیتی
ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
ADMIN_EMAIL=$ADMIN_EMAIL
SECRET_KEY=$(openssl rand -hex 32)

# تنظیمات پنل
PANEL_PORT=$PANEL_PORT
PANEL_DOMAIN=$PANEL_DOMAIN
DEFAULT_THEME=$DEFAULT_THEME
DEFAULT_LANGUAGE=$DEFAULT_LANGUAGE
EOF

    chmod 600 "$BACKEND_DIR/.env"
    chown "$SERVICE_USER":"$SERVICE_USER" "$BACKEND_DIR/.env"
    
    success "فایل .env در $BACKEND_DIR/.env ایجاد شد"
}

# ------------------- تنظیم سرویس پنل -------------------
setup_panel_service() {
    info "تنظیم سرویس پنل..."
    
    APP_FILE="$BACKEND_DIR/app.py"
    if [[ ! -f "$APP_FILE" ]]; then
        warning "فایل app.py در مسیر $BACKEND_DIR یافت نشد! یک فایل نمونه ایجاد می‌کنیم..."
        cat > "$APP_FILE" <<EOF
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
import json

app = FastAPI()

# تنظیمات CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/api/v1/xray/config")
async def get_xray_config():
    try:
        conn = psycopg2.connect("dbname=zhina_db user=zhina_user")
        cursor = conn.cursor()
        cursor.execute("SELECT settings FROM inbounds")
        results = cursor.fetchall()
        configs = [json.loads(row[0]) for row in results]
        return JSONResponse(status_code=200, content={"status": "success", "data": configs})
    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

@app.get("/")
async def root():
    return {"message": "خوش آمدید به پنل مدیریت Zhina"}
EOF
    fi
    
    cat > /etc/systemd/system/zhina-panel.service <<EOF
[Unit]
Description=Zhina Panel Service
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$BACKEND_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
Environment="PYTHONPATH=$BACKEND_DIR"
ExecStart=$INSTALL_DIR/venv/bin/uvicorn \
    app:app \
    --host 0.0.0.0 \
    --port $PANEL_PORT \
    --workers $UVICORN_WORKERS \
    --log-level info \
    --access-log \
    --no-server-header

Restart=always
RestartSec=3
StandardOutput=append:$LOG_DIR/panel/access.log
StandardError=append:$LOG_DIR/panel/error.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now zhina-panel || error "خطا در راه‌اندازی سرویس پنل"
    
    sleep 3
    if ! systemctl is-active --quiet zhina-panel; then
        journalctl -u zhina-panel -n 30 --no-pager
        error "سرویس پنل فعال نشد. لطفاً خطاهای بالا را بررسی کنید."
    fi
    
    success "سرویس پنل تنظیم شد"
}

# ------------------- نمایش اطلاعات نصب -------------------
show_installation_info() {
    local panel_url="https://${PANEL_DOMAIN}"
    if [[ "$PANEL_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        panel_url="http://${PANEL_DOMAIN}:${PANEL_PORT}"
    fi
    
    echo -e "\n${GREEN}=== نصب با موفقیت کامل شد ===${NC}"
    echo -e "\n${YELLOW}مشخصات دسترسی:${NC}"
    echo -e "• پنل مدیریت: ${GREEN}${panel_url}${NC}"
    echo -e "• کاربر ادمین: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "• رمز عبور ادمین: ${YELLOW}${ADMIN_PASS}${NC}"
    echo -e "• ایمیل ادمین: ${YELLOW}${ADMIN_EMAIL}${NC}"
    
    echo -e "\n${YELLOW}تنظیمات Xray:${NC}"
    echo -e "• UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "• Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    echo -e "• Short ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
    echo -e "• مسیر WS: ${YELLOW}${XRAY_PATH}${NC}"
    echo -e "• رمز عبور Trojan: ${YELLOW}${TROJAN_PASSWORD}${NC}"
    echo -e "• رمز عبور Shadowsocks: ${YELLOW}${SHADOWSOCKS_PASSWORD}${NC}"
    echo -e "• اطلاعات SOCKS: ${YELLOW}${SOCKS_USERNAME}:${SOCKS_PASSWORD}${NC}"
    
    echo -e "\n${YELLOW}اطلاعات دیتابیس:${NC}"
    echo -e "• نام دیتابیس: ${YELLOW}${DB_NAME}${NC}"
    echo -e "• کاربر دیتابیس: ${YELLOW}${DB_USER}${NC}"
    echo -e "• رمز عبور دیتابیس: ${YELLOW}${DB_PASSWORD}${NC}"
    
    echo -e "\n${YELLOW}دستورات مدیریت:${NC}"
    echo -e "• وضعیت سرویس‌ها: ${GREEN}systemctl status xray nginx zhina-panel postgresql${NC}"
    echo -e "• مشاهده لاگ پنل: ${GREEN}tail -f $LOG_DIR/panel/{access,error}.log${NC}"
    echo -e "• مشاهده لاگ Xray: ${GREEN}journalctl -u xray -f${NC}"
    
    cat > "$INSTALL_DIR/installation-info.txt" <<EOF
=== Zhina Panel Installation Details ===

Panel URL: ${panel_url}
Admin Username: ${ADMIN_USER}
Admin Email: ${ADMIN_EMAIL}
Admin Password: ${ADMIN_PASS}

Database Info:
- Database: ${DB_NAME}
- Username: ${DB_USER}
- Password: ${DB_PASSWORD}

Xray Settings:
- VLESS+Reality:
  • Port: 8443
  • UUID: ${XRAY_UUID}
  • Public Key: ${REALITY_PUBLIC_KEY}
  • Short ID: ${REALITY_SHORT_ID}
- VMESS+WS:
  • Port: ${XRAY_HTTP_PORT}
  • Path: ${XRAY_PATH}
- Trojan:
  • Port: 8444
  • Password: ${TROJAN_PASSWORD}
- Shadowsocks:
  • Port: 8388
  • Password: ${SHADOWSOCKS_PASSWORD}
  • Method: aes-256-gcm
- SOCKS:
  • Port: 10808
  • Username: ${SOCKS_USERNAME}
  • Password: ${SOCKS_PASSWORD}
- HTTP:
  • Port: 8080
- gRPC:
  • Port: 50051
  • Service Name: grpcservice
- Dokodemo-Door:
  • Port: 10000
  • Target: 8.8.8.8:53

Log Files:
- Panel Access: ${LOG_DIR}/panel/access.log
- Panel Errors: ${LOG_DIR}/panel/error.log
- Xray Logs: /var/log/zhina/xray-{access,error}.log
EOF

    chmod 600 "$INSTALL_DIR/installation-info.txt"
    chown "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR/installation-info.txt"
}

# ------------------- تابع اصلی -------------------
main() {
    clear
    echo -e "${GREEN}"
    echo "   __  ___      _     _       __  "
    echo "  /  |/  /__  (_)___(_)___  / /_ "
    echo " / /|_/ / _ \/ / __/ / __ \/ __/ "
    echo "/_/  /_/_//_/_/_/ /_/_/ /_/\__/  "
    echo -e "${NC}"
    echo -e "${YELLOW}=== راه‌اندازی Zhina Panel ===${NC}"

    echo "📌 بررسی سیستم..."
    check_system && echo "✅ بررسی سیستم انجام شد."

    echo "📌 دریافت اطلاعات مدیر..."
    get_admin_credentials && echo "✅ اطلاعات مدیر ثبت شد."

    echo "📌 نصب پیش‌نیازها..."
    set -x
    install_prerequisites
    set +x
    echo "✅ پیش‌نیازها نصب شدند."

    echo "📌 تنظیم محیط..."
    setup_environment && echo "✅ محیط تنظیم شد."

    echo "📌 تنظیم پایگاه داده..."
    setup_database && echo "✅ پایگاه داده راه‌اندازی شد."

    echo "📌 تنظیم Python..."
    setup_python && echo "✅ Python تنظیم شد."

    echo "📌 تنظیم Nginx..."
    setup_nginx && echo "✅ Nginx پیکربندی شد."

    echo "📌 تنظیم SSL..."
    setup_ssl && echo "✅ SSL پیکربندی شد."

    echo "📌 تنظیم Xray..."
    setup_xray && echo "✅ Xray تنظیم شد."

    echo "📌 تنظیم متغیرهای محیطی..."
    setup_env && echo "✅ متغیرهای محیطی تنظیم شدند."

    echo "📌 تنظیم سرویس پنل..."
    setup_panel_service && echo "✅ سرویس پنل راه‌اندازی شد."

    echo "📌 ایجاد منوی مدیریت..."
    create_management_menu && echo "✅ منوی مدیریت آماده شد."

    echo -e "
${GREEN}برای مشاهده جزئیات کامل، فایل لاگ را بررسی کنید:${NC}"
    echo -e "${YELLOW}tail -f /var/log/zhina-install.log${NC}"
    echo -e "
${GREEN}برای مدیریت پنل از دستور زیر استفاده کنید:${NC}"
    echo -e "${YELLOW}zhina-manager${NC}"
}

main
