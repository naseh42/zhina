#!/bin/bash

# رنگ‌ها برای نمایش پیام‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# توابع پیام
error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# بررسی دسترسی root
if [ "$EUID" -ne 0 ]; then
    error "لطفاً با دسترسی root اجرا کنید."
fi

# تنظیم مسیرها
INSTALL_DIR="/var/lib/$(hostname -s)_setup"
TEMP_DIR="/tmp/$(hostname -s)_setup_temp"

# بررسی و تنظیم دسترسی‌ها
info "بررسی و تنظیم دایرکتوری نصب..."
mkdir -p $INSTALL_DIR
chmod -R 755 $INSTALL_DIR || error "خطا در تنظیم دایرکتوری نصب."
mkdir -p $TEMP_DIR
chmod -R 755 $TEMP_DIR || error "خطا در تنظیم دایرکتوری موقت."

# نصب پیش‌نیازها
info "در حال نصب پیش‌نیازها..."
apt update
apt install -y curl openssl nginx python3 python3-venv python3-pip postgresql postgresql-contrib certbot || error "خطا در نصب پیش‌نیازها."

# دریافت اطلاعات کاربر
read -p "دامنه خود را وارد کنید (اختیاری): " DOMAIN
read -p "پورت پنل را وارد کنید (پیش‌فرض: 8000): " PORT
PORT=${PORT:-8000}
read -p "یوزرنیم ادمین: " ADMIN_USERNAME
read -s -p "پسورد ادمین: " ADMIN_PASSWORD
echo ""
DB_PASSWORD=$(openssl rand -hex 12)

# ایجاد فایل .env
info "ایجاد فایل .env..."
cat <<EOF > $TEMP_DIR/.env
ADMIN_USERNAME='${ADMIN_USERNAME:-admin}'
ADMIN_PASSWORD='${ADMIN_PASSWORD:-admin}'
DB_PASSWORD='$DB_PASSWORD'
DATABASE_URL='postgresql://vpnuser:$DB_PASSWORD@localhost/vpndb'
EOF

# انتقال به مسیر نصب
mkdir -p $INSTALL_DIR/backend/
mv $TEMP_DIR/.env $INSTALL_DIR/backend/.env || error "خطا در انتقال فایل .env."
chmod 600 $INSTALL_DIR/backend/.env
# تنظیم پایگاه داده
info "تنظیم پایگاه داده و کاربر..."
sudo -u postgres psql -c "CREATE DATABASE vpndb;" 2>/dev/null || info "پایگاه داده از قبل وجود دارد."
USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='vpnuser'")

if [ "$USER_EXISTS" == "1" ]; then
    info "کاربر vpnuser از قبل وجود دارد، پسورد ریست می‌شود..."
    sudo -u postgres psql -c "ALTER USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ریست پسورد."
else
    info "ایجاد کاربر vpnuser..."
    sudo -u postgres psql -c "CREATE USER vpnuser WITH PASSWORD '$DB_PASSWORD';" || error "خطا در ایجاد کاربر."
fi

info "ایجاد دسترسی‌ها..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE vpndb TO vpnuser;" || error "خطا در اعطای دسترسی‌ها."

# ایجاد اسکریپت بررسی و ساخت جداول به‌صورت خودکار
info "ایجاد اسکریپت بررسی فایل‌های مدل و ساخت جداول..."
cat <<EOF > $TEMP_DIR/dynamic_setup_db.py
import os
import psycopg2
import re

# اتصال به پایگاه داده
conn = psycopg2.connect("dbname='vpndb' user='vpnuser' password='${DB_PASSWORD}' host='localhost'")
cursor = conn.cursor()

# مسیر پروژه
project_dir = "${INSTALL_DIR}"

# تشخیص فایل‌های مدل
def find_model_files(directory):
    model_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".py"):
                file_path = os.path.join(root, file)
                with open(file_path, "r", encoding="utf-8") as f:
                    content = f.read()
                    if "Base" in content and ("Column" in content or "Integer" in content or "String" in content):
                        model_files.append(file_path)
    return model_files

# استخراج تعریف جداول
def extract_table_definitions(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()
        tables = re.findall(r"class\s+(\w+)\s*\(.*Base.*\):", content)
        columns = re.findall(r"(\w+)\s*=\s*Column\((.*?)\)", content)
        return tables, columns

# ساخت جداول
def create_tables():
    model_files = find_model_files(project_dir)
    print(f"فایل‌های مدل پیدا شد: {model_files}")

    for model_file in model_files:
        tables, columns = extract_table_definitions(model_file)
        for table in tables:
            print(f"ساخت جدول: {table}")
            column_defs = ", ".join([f"{col[0]} {col[1]}" for col in columns])
            create_table_query = f"CREATE TABLE IF NOT EXISTS {table} ({column_defs});"
            cursor.execute(create_table_query)

    conn.commit()
    cursor.close()
    conn.close()
    print("تمام جداول با موفقیت ایجاد شدند.")

# اجرای ساخت جداول
create_tables()
EOF

# اجرای اسکریپت ساخت جداول
info "اجرای اسکریپت ساخت جداول..."
python3 $TEMP_DIR/dynamic_setup_db.py || error "خطا در اجرای اسکریپت."
# بررسی فایل‌های Nginx
info "بررسی و مدیریت فایل‌های Nginx..."
NGINX_CONFIG="/etc/nginx/sites-available/zhina"

if [ -f "$NGINX_CONFIG" ]; then
    info "فایل Nginx از قبل وجود دارد. حذف می‌شود..."
    rm -f $NGINX_CONFIG
fi

# بررسی و حذف فایل‌های تکراری در مسیر sites-enabled
for file in /etc/nginx/sites-enabled/*; do
    if grep -q "159.65.95.66" "$file"; then
        info "حذف فایل تکراری: $file"
        rm -f "$file"
    fi
done

# ایجاد فایل جدید برای تنظیمات
cat <<EOF > $NGINX_CONFIG
server {
    listen 80;
    server_name ${DOMAIN:-$(curl -s ifconfig.me)};

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

ln -sf $NGINX_CONFIG /etc/nginx/sites-enabled/zhina
sudo nginx -t || error "خطا در تست تنظیمات Nginx."
sudo systemctl reload nginx || error "خطا در راه‌اندازی مجدد Nginx."
# نصب Xray
info "نصب Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# تنظیم فایل Xray با پروتکل‌های کامل
info "تنظیم فایل Xray..."
cat <<EOF > /etc/xray/config.json
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$(uuidgen)"}]}
    },
    {
      "port": 8443,
      "protocol": "vmess",
      "settings": {"clients": [{"id": "$(uuidgen)"}]}
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$(openssl rand -hex 16)"}]}
    },
    {
      "port": 8080,
      "protocol": "http"
    },
    {
      "port": 9000,
      "protocol": "tcp"
    },
    {
      "port": 1984,
      "protocol": "kcp"
    },
    {
      "port": 8989,
      "protocol": "quic"
    },
    {
      "port": 2002,
      "protocol": "grpc"
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

sudo systemctl restart xray || error "خطا در راه‌اندازی Xray."

# باز کردن پورت‌های موردنیاز
info "باز کردن پورت‌های موردنیاز..."
PORTS=(443 8443 2083 8080 9000 1984 8989 2002)

for port in "${PORTS[@]}"; do
    ufw allow $port/tcp || info "پورت $port/tcp از قبل باز است."
    ufw allow $port/udp || info "پورت $port/udp از قبل باز است."
done
ufw reload || error "خطا در بارگذاری مجدد فایروال."
# نمایش اطلاعات دسترسی و پروتکل‌ها
success "نصب کامل و موفقیت‌آمیز انجام شد!"
info "====== اطلاعات دسترسی ======"
echo -e "${GREEN}• آدرس پنل: http://${DOMAIN:-$(curl -s ifconfig.me)}:${PORT}${NC}"
echo -e "• یوزرنیم: ${ADMIN_USERNAME:-admin}"
echo -e "• پسورد: ${ADMIN_PASSWORD:-admin}${NC}"

info "\n====== اطلاعات پروتکل‌ها ======"
echo -e "${GREEN}🔰 VLESS:"
echo -e "  پورت: 443"
echo -e "  UUID: $(uuidgen)${NC}"

echo -e "${GREEN}🌀 VMESS:"
echo -e "  پورت: 8443"
echo -e "  UUID: $(uuidgen)${NC}"

echo -e "${GREEN}⚔️ Trojan:"
echo -e "  پورت: 2083"
echo -e "  پسورد: $(openssl rand -hex 16)${NC}"

echo -e "${GREEN}🌐 HTTP:"
echo -e "  پورت: 8080${NC}"

echo -e "${GREEN}📡 TCP:"
echo -e "  پورت: 9000${NC}"

echo -e "${GREEN}💡 KCP:"
echo -e "  پورت: 1984${NC}"

echo -e "${GREEN}📶 QUIC:"
echo -e "  پورت: 8989${NC}"

echo -e "${GREEN}🔗 GRPC:"
echo -e "  پورت: 2002${NC}"

success "تمامی پروتکل‌ها تنظیم شدند و سرور آماده استفاده است!"
