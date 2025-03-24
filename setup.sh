#!/bin/bash
set -euo pipefail

# ----- تنظیمات اصلی -----
INSTALL_DIR="/var/lib/zhina"
TEMP_DIR="/tmp/zhina_temp"
REPO_URL="https://github.com/naseh42/zhina.git"
DB_NAME="zhina_db"
DB_USER="zhina_user"
XRAY_PORT=443
PANEL_PORT=8000

# ----- رنگ‌ها و توابع -----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
info() { echo -e "${YELLOW}[INFO] $1${NC}"; }

# ----- توابع اصلی -----
create_requirements() {
    info "Creating requirements.txt..."
    cat > "$INSTALL_DIR/requirements.txt" <<EOF
sqlalchemy==2.0.28
psycopg2-binary==2.9.9
fastapi==0.103.2
uvicorn==0.23.2
python-multipart==0.0.6
jinja2==3.1.2
python-dotenv==1.0.0
EOF
}

setup_database() {
    info "Configuring PostgreSQL..."
    local DB_PASS=$(openssl rand -hex 16)
    
    sudo -u postgres psql <<EOF
    DROP DATABASE IF EXISTS $DB_NAME;
    DROP ROLE IF EXISTS $DB_USER;
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
    CREATE DATABASE $DB_NAME;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

    echo "host all all 127.0.0.1/32 md5" | sudo tee -a /etc/postgresql/*/main/pg_hba.conf
    systemctl restart postgresql

    # ذخیره اطلاعات در env
    cat > "$INSTALL_DIR/.env" <<EOF
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME
SECRET_KEY=$(openssl rand -hex 32)
EOF
}

install_panel() {
    info "Installing control panel..."
    git clone "$REPO_URL" "$TEMP_DIR"
    cp -r "$TEMP_DIR"/* "$INSTALL_DIR"/
    
    # اگر requirements.txt وجود نداشت بساز
    [[ ! -f "$INSTALL_DIR/requirements.txt" ]] && create_requirements
    
    python3 -m venv "$INSTALL_DIR/venv"
    source "$INSTALL_DIR/venv/bin/activate"
    pip install -r "$INSTALL_DIR/requirements.txt"
}

# ----- اجرای اصلی -----
main() {
    [[ $EUID -ne 0 ]] && error "نیاز به دسترسی root دارد!"
    rm -rf "$INSTALL_DIR" "$TEMP_DIR"
    mkdir -p "$INSTALL_DIR"
    
    apt-get update
    apt-get install -y git python3 python3-venv python3-pip postgresql
    
    setup_database
    install_panel
    
    success "نصب کامل شد!"
    echo -e "\n=== اطلاعات دسترسی ==="
    echo "مسیر نصب: $INSTALL_DIR"
    echo "پورت پنل: $PANEL_PORT"
    echo "فعال سازی محیط: source $INSTALL_DIR/venv/bin/activate"
    echo "اجرای پنل: uvicorn main:app --port $PANEL_PORT"
}

main
