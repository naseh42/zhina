#!/bin/bash

# ==============================================
# Xray Ultimate Installer (v3.0)
# Complete 700-line script with all features:
# - Automatic domain/IP detection
# - Self-signed certificates
# - Custom port selection
# - Multiple protocol support
# - Nginx reverse proxy
# - IPv6 support
# - Telemetry
# - Client info generation
# - QR code generation
# ==============================================

# Global Configurations
XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_SERVICE="/etc/systemd/system/xray.service"
NGINX_CONFIG="/etc/nginx/sites-available/xray.conf"
TEMP_DIR="/tmp/xray-setup"
LOG_FILE="/var/log/xray-setup.log"
CLIENT_INFO="/root/xray_client_info.txt"

# Color Definitions
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m'

# Default Values
DEFAULT_PORT=8443
DEFAULT_PROTOCOL="vmess"
DEFAULT_EMAIL="admin@yourdomain.com"
DEFAULT_PATH="/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)"

# System Variables
OS=""
OS_VERSION=""
ARCH=""
IPV4=""
IPV6=""

# User Variables
DOMAIN=""
PORT=""
PROTOCOL=""
EMAIL=""
UUID=""
PATH=""
SELF_SIGNED=false
TELEMETRY=false

# ========================
# Core Functions
# ========================

function initialize() {
    echo -e "${GREEN}[+] Initializing Xray Installer...${NC}"
    
    # Create temp directory
    mkdir -p $TEMP_DIR
    touch $LOG_FILE
    
    # Check root access
    check_root
    
    # Detect system info
    detect_os
    detect_architecture
    detect_ips
    
    # Install dependencies
    install_dependencies
    
    echo -e "${GREEN}[+] System initialization completed${NC}"
}

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[-] This script must be run as root${NC}" 1>&2
        exit 1
    fi
}

function detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/centos-release ]; then
        OS="centos"
        OS_VERSION=$(cat /etc/centos-release | sed 's/.* \([0-9]\).*/\1/')
    else
        echo -e "${RED}[-] Could not detect OS${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[i] Detected OS: $OS $OS_VERSION${NC}"
}

function detect_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        *) echo -e "${RED}[-] Unsupported architecture: $ARCH${NC}"; exit 1 ;;
    esac
    
    echo -e "${BLUE}[i] Architecture: $ARCH${NC}"
}

function detect_ips() {
    IPV4=$(curl -4 -s icanhazip.com)
    IPV6=$(curl -6 -s icanhazip.com || echo "Not available")
    
    echo -e "${BLUE}[i] IPv4: $IPV4${NC}"
    [[ "$IPV6" != "Not available" ]] && echo -e "${BLUE}[i] IPv6: $IPV6${NC}"
}

function install_dependencies() {
    echo -e "${YELLOW}[~] Installing dependencies...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt-get update >> $LOG_FILE 2>&1
            apt-get install -y \
                curl wget unzip \
                certbot nginx \
                socat net-tools \
                openssl qrencode >> $LOG_FILE 2>&1
            ;;
        centos|fedora)
            yum install -y \
                curl wget unzip \
                certbot nginx \
                socat net-tools \
                openssl qrencode >> $LOG_FILE 2>&1
            ;;
        *)
            echo -e "${RED}[-] Unsupported OS for automatic dependencies${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}[+] Dependencies installed${NC}"
}

# ========================
# User Interaction
# ========================

function get_user_input() {
    clear
    show_banner
    
    # Domain input
    while true; do
        read -p "$(echo -e "${BLUE}[?] Enter your domain (leave blank for self-signed IP): ${NC}")" DOMAIN
        
        if [ -z "$DOMAIN" ]; then
            SELF_SIGNED=true
            DOMAIN="$IPV4.sslip.io"
            echo -e "${YELLOW}[!] Using self-signed certificate for: $DOMAIN${NC}"
            break
        elif [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            SELF_SIGNED=false
            break
        else
            echo -e "${RED}[-] Invalid domain format${NC}"
        fi
    done
    
    # Port selection
    while true; do
        read -p "$(echo -e "${BLUE}[?] Enter Xray port [default: $DEFAULT_PORT]: ${NC}")" PORT
        PORT=${PORT:-$DEFAULT_PORT}
        
        if [[ $PORT =~ ^[0-9]+$ ]] && [ $PORT -gt 0 ] && [ $PORT -lt 65536 ]; then
            break
        else
            echo -e "${RED}[-] Invalid port number${NC}"
        fi
    done
    
    # Protocol selection
    echo -e "${BLUE}[?] Select protocol:${NC}"
    echo "1) VMess (default)"
    echo "2) VLESS"
    echo "3) Trojan"
    echo "4) Shadowsocks"
    while true; do
        read -p "$(echo -e "${BLUE}[?] Enter your choice [1-4]: ${NC}")" PROTOCOL_CHOICE
        case $PROTOCOL_CHOICE in
            1) PROTOCOL="vmess"; break ;;
            2) PROTOCOL="vless"; break ;;
            3) PROTOCOL="trojan"; break ;;
            4) PROTOCOL="shadowsocks"; break ;;
            "") PROTOCOL="vmess"; break ;;
            *) echo -e "${RED}[-] Invalid choice${NC}" ;;
        esac
    done
    
    # Email for Let's Encrypt
    if [ "$SELF_SIGNED" = false ]; then
        while true; do
            read -p "$(echo -e "${BLUE}[?] Enter email for Let's Encrypt [default: $DEFAULT_EMAIL]: ${NC}")" EMAIL
            EMAIL=${EMAIL:-$DEFAULT_EMAIL}
            
            if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                echo -e "${RED}[-] Invalid email format${NC}"
            fi
        done
    fi
    
    # Path selection
    read -p "$(echo -e "${BLUE}[?] Enter WebSocket path [default: random]: ${NC}")" PATH
    PATH=${PATH:-$DEFAULT_PATH}
    
    # Telemetry option
    read -p "$(echo -e "${BLUE}[?] Enable telemetry? [y/N]: ${NC}")" TELEMETRY_RESPONSE
    if [[ $TELEMETRY_RESPONSE =~ ^[Yy]$ ]]; then
        TELEMETRY=true
    fi
    
    # Generate UUID
    UUID=$(generate_uuid)
}

function show_banner() {
    clear
    echo -e "${PURPLE}"
    echo "  __  _____  ___  _ __ ___ "
    echo "  \ \/ / __|/ _ \| '__/ __|"
    echo "   >  <\__ \ (_) | |  \__ \\"
    echo "  /_/\_\___/\___/|_|  |___/"
    echo -e "${NC}"
    echo -e "${CYAN}  Xray Ultimate Installer v3.0${NC}"
    echo -e "${CYAN}--------------------------------${NC}"
    echo
}

# ========================
# Certificate Management
# ========================

function setup_certificates() {
    echo -e "${YELLOW}[~] Setting up SSL certificates...${NC}"
    
    if [ "$SELF_SIGNED" = true ]; then
        generate_self_signed_cert
    else
        obtain_letsencrypt_cert
    fi
    
    echo -e "${GREEN}[+] SSL certificates configured${NC}"
}

function generate_self_signed_cert() {
    echo -e "${YELLOW}[~] Generating self-signed certificate for $DOMAIN...${NC}"
    
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
        -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
        -subj "/CN=$DOMAIN" >> $LOG_FILE 2>&1
    
    # Create dummy files for Nginx
    touch /etc/letsencrypt/live/$DOMAIN/cert.pem
    touch /etc/letsencrypt/live/$DOMAIN/chain.pem
}

function obtain_letsencrypt_cert() {
    echo -e "${YELLOW}[~] Obtaining Let's Encrypt certificate for $DOMAIN...${NC}"
    
    # Stop Nginx temporarily
    systemctl stop nginx >> $LOG_FILE 2>&1
    
    # Obtain certificate
    certbot certonly --standalone --non-interactive --agree-tos \
        --email $EMAIL -d $DOMAIN >> $LOG_FILE 2>&1
    
    # Restart Nginx
    systemctl start nginx >> $LOG_FILE 2>&1
    
    # Create symlinks for Xray
    ln -sf /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/cert.pem
    ln -sf /etc/letsencrypt/live/$DOMAIN/chain.pem /etc/letsencrypt/live/$DOMAIN/chain.pem
}

# ========================
# Xray Installation
# ========================

function install_xray() {
    echo -e "${YELLOW}[~] Installing Xray...${NC}"
    
    # Download Xray
    LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep tag_name | cut -d '"' -f 4)
    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/$LATEST_VERSION/Xray-linux-$ARCH.zip"
    
    echo -e "${BLUE}[i] Downloading Xray $LATEST_VERSION...${NC}"
    wget $DOWNLOAD_URL -O $TEMP_DIR/xray.zip >> $LOG_FILE 2>&1
    
    # Extract files
    unzip $TEMP_DIR/xray.zip -d $TEMP_DIR >> $LOG_FILE 2>&1
    
    # Install binaries
    mv $TEMP_DIR/xray /usr/local/bin/
    mv $TEMP_DIR/geo* /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # Create directories
    mkdir -p /var/log/xray
    mkdir -p /usr/local/etc/xray
    
    # Create service file
    create_service_file
    
    echo -e "${GREEN}[+] Xray installed successfully${NC}"
}

function create_service_file() {
    cat > $XRAY_SERVICE <<EOF
[Unit]
Description=Xray Service
Documentation=https://xtls.github.io
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config $XRAY_CONFIG
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >> $LOG_FILE 2>&1
}

# ========================
# Configuration Generation
# ========================

function generate_config() {
    echo -e "${YELLOW}[~] Generating Xray configuration...${NC}"
    
    case $PROTOCOL in
        vmess)
            generate_vmess_config
            ;;
        vless)
            generate_vless_config
            ;;
        trojan)
            generate_trojan_config
            ;;
        shadowsocks)
            generate_shadowsocks_config
            ;;
    esac
    
    # Enable telemetry if requested
    if [ "$TELEMETRY" = true ]; then
        enable_telemetry
    fi
    
    echo -e "${GREEN}[+] Xray configuration generated${NC}"
}

function generate_vmess_config() {
    cat > $XRAY_CONFIG <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0,
            "email": "$EMAIL"
          }
        ],
        "disableInsecureEncryption": true
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
            }
          ],
          "alpn": ["http/1.1"]
        },
        "wsSettings": {
          "path": "$PATH",
          "headers": {
            "Host": "$DOMAIN"
          }
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
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
}

function generate_vless_config() {
    cat > $XRAY_CONFIG <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-direct",
            "email": "$EMAIL"
          }
        ],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
            }
          ],
          "alpn": ["http/1.1"]
        },
        "wsSettings": {
          "path": "$PATH",
          "headers": {
            "Host": "$DOMAIN"
          }
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
}

function generate_trojan_config() {
    cat > $XRAY_CONFIG <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "$UUID",
            "email": "$EMAIL",
            "flow": "xtls-rprx-direct"
          }
        ],
        "fallbacks": []
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/$DOMAIN/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/$DOMAIN/privkey.pem"
            }
          ],
          "alpn": ["http/1.1"]
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
}

function generate_shadowsocks_config() {
    local PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    
    cat > $XRAY_CONFIG <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-256-gcm",
        "password": "$PASSWORD",
        "network": "tcp,udp",
        "level": 0
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
    
    # Update UUID variable for client info
    UUID=$PASSWORD
}

function enable_telemetry() {
    echo -e "${YELLOW}[~] Enabling telemetry...${NC}"
    
    # Backup original config
    cp $XRAY_CONFIG $XRAY_CONFIG.bak
    
    # Add telemetry section
    sed -i '/"log":/a \    "stats": {},\n    "policy": {\n      "levels": {\n        "0": {\n          "statsUserUplink": true,\n          "statsUserDownlink": true\n        }\n      },\n      "system": {\n        "statsInboundUplink": true,\n        "statsInboundDownlink": true\n      }\n    },' $XRAY_CONFIG
    
    echo -e "${GREEN}[+] Telemetry enabled${NC}"
}

# ========================
# Nginx Configuration
# ========================

function configure_nginx() {
    echo -e "${YELLOW}[~] Configuring Nginx...${NC}"
    
    # Create basic Nginx config
    cat > $NGINX_CONFIG <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    
    # ACME challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    # Redirect all other HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;
    
    # SSL certificates
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    # SSL protocols
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    
    # Root location
    location / {
        root /var/www/html;
        index index.html;
    }
EOF

    # Add proxy settings for WebSocket protocols
    if [[ "$PROTOCOL" == "vmess" || "$PROTOCOL" == "vless" ]]; then
        cat >> $NGINX_CONFIG <<EOF
    
    # WebSocket path
    location $PATH {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
EOF
    fi

    # Close server block
    echo "}" >> $NGINX_CONFIG
    
    # Enable configuration
    ln -sf $NGINX_CONFIG /etc/nginx/sites-enabled/ >> $LOG_FILE 2>&1
    
    # Create web root
    mkdir -p /var/www/html
    echo "<!DOCTYPE html><html><head><title>Welcome</title></head><body><h1>Welcome to $DOMAIN</h1></body></html>" > /var/www/html/index.html
    
    # Test and restart Nginx
    nginx -t >> $LOG_FILE 2>&1
    systemctl restart nginx >> $LOG_FILE 2>&1
    
    echo -e "${GREEN}[+] Nginx configured successfully${NC}"
}

# ========================
# Firewall Configuration
# ========================

function configure_firewall() {
    echo -e "${YELLOW}[~] Configuring firewall...${NC}"
    
    # Check if UFW is available
    if command -v ufw &> /dev/null; then
        ufw allow $PORT/tcp >> $LOG_FILE 2>&1
        ufw allow 80/tcp >> $LOG_FILE 2>&1
        ufw allow 443/tcp >> $LOG_FILE 2>&1
        echo -e "${GREEN}[+] Firewall rules added${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$PORT/tcp >> $LOG_FILE 2>&1
        firewall-cmd --permanent --add-service=http >> $LOG_FILE 2>&1
        firewall-cmd --permanent --add-service=https >> $LOG_FILE 2>&1
        firewall-cmd --reload >> $LOG_FILE 2>&1
        echo -e "${GREEN}[+] Firewall rules added${NC}"
    else
        echo -e "${YELLOW}[!] No supported firewall manager found${NC}"
    fi
}

# ========================
# Utility Functions
# ========================

function generate_uuid() {
    if command -v xray &> /dev/null; then
        xray uuid
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

function generate_qr_code() {
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW}[!] qrencode not installed, skipping QR code generation${NC}"
        return
    fi
    
    echo -e "${CYAN}\n=== QR Code Configuration ===${NC}"
    
    case $PROTOCOL in
        vmess)
            local VMESS_CONFIG="{
                \"v\": \"2\",
                \"ps\": \"Xray-VMess\",
                \"add\": \"$DOMAIN\",
                \"port\": \"443\",
                \"id\": \"$UUID\",
                \"aid\": \"0\",
                \"scy\": \"auto\",
                \"net\": \"ws\",
                \"type\": \"none\",
                \"host\": \"$DOMAIN\",
                \"path\": \"$PATH\",
                \"tls\": \"tls\",
                \"sni\": \"$DOMAIN\"
            }"
            echo -e "${GREEN}VMess Configuration:${NC}"
            echo $VMESS_CONFIG | jq .
            echo -e "\n${GREEN}VMess QR Code:${NC}"
            echo $VMESS_CONFIG | base64 -w 0 | qrencode -t ANSIUTF8
            ;;
        vless)
            local VLESS_URL="vless://$UUID@$DOMAIN:443?type=ws&security=tls&path=$PATH&host=$DOMAIN&sni=$DOMAIN#Xray-VLess"
            echo -e "${GREEN}VLess Configuration URL:${NC}"
            echo $VLESS_URL
            echo -e "\n${GREEN}VLess QR Code:${NC}"
            echo $VLESS_URL | qrencode -t ANSIUTF8
            ;;
        trojan)
            local TROJAN_URL="trojan://$UUID@$DOMAIN:443?type=tcp&security=tls&sni=$DOMAIN#Xray-Trojan"
            echo -e "${GREEN}Trojan Configuration URL:${NC}"
            echo $TROJAN_URL
            echo -e "\n${GREEN}Trojan QR Code:${NC}"
            echo $TROJAN_URL | qrencode -t ANSIUTF8
            ;;
        shadowsocks)
            local SS_URL="ss://$(echo -n "aes-256-gcm:$UUID" | base64 -w 0)@$DOMAIN:$PORT#Xray-Shadowsocks"
            echo -e "${GREEN}Shadowsocks Configuration URL:${NC}"
            echo $SS_URL
            echo -e "\n${GREEN}Shadowsocks QR Code:${NC}"
            echo $SS_URL | qrencode -t ANSIUTF8
            ;;
    esac
}

function generate_client_info() {
    echo -e "${CYAN}\n=== Client Configuration ===${NC}" > $CLIENT_INFO
    echo -e "Domain: $DOMAIN" >> $CLIENT_INFO
    echo -e "Port: 443" >> $CLIENT_INFO
    echo -e "Protocol: $PROTOCOL" >> $CLIENT_INFO
    
    case $PROTOCOL in
        vmess)
            echo -e "\nVMess Settings:" >> $CLIENT_INFO
            echo -e "Address: $DOMAIN" >> $CLIENT_INFO
            echo -e "Port: 443" >> $CLIENT_INFO
            echo -e "ID: $UUID" >> $CLIENT_INFO
            echo -e "Alter ID: 0" >> $CLIENT_INFO
            echo -e "Security: auto" >> $CLIENT_INFO
            echo -e "Network: ws" >> $CLIENT_INFO
            echo -e "Path: $PATH" >> $CLIENT_INFO
            echo -e "TLS: tls" >> $CLIENT_INFO
            ;;
        vless)
            echo -e "\nVLESS Settings:" >> $CLIENT_INFO
            echo -e "Address: $DOMAIN" >> $CLIENT_INFO
            echo -e "Port: 443" >> $CLIENT_INFO
            echo -e "ID: $UUID" >> $CLIENT_INFO
            echo -e "Flow: xtls-rprx-direct" >> $CLIENT_INFO
            echo -e "Network: ws" >> $CLIENT_INFO
            echo -e "Path: $PATH" >> $CLIENT_INFO
            echo -e "TLS: tls" >> $CLIENT_INFO
            ;;
        trojan)
            echo -e "\nTrojan Settings:" >> $CLIENT_INFO
            echo -e "Address: $DOMAIN" >> $CLIENT_INFO
            echo -e "Port: 443" >> $CLIENT_INFO
            echo -e "Password: $UUID" >> $CLIENT_INFO
            echo -e "Flow: xtls-rprx-direct" >> $CLIENT_INFO
            echo -e "TLS: tls" >> $CLIENT_INFO
            ;;
        shadowsocks)
            echo -e "\nShadowsocks Settings:" >> $CLIENT_INFO
            echo -e "Address: $DOMAIN" >> $CLIENT_INFO
            echo -e "Port: $PORT" >> $CLIENT_INFO
            echo -e "Method: aes-256-gcm" >> $CLIENT_INFO
            echo -e "Password: $UUID" >> $CLIENT_INFO
            ;;
    esac
    
    echo -e "\nConfiguration saved to: $CLIENT_INFO"
}

# ========================
# Finalization
# ========================

function finalize_installation() {
    # Start services
    systemctl enable xray >> $LOG_FILE 2>&1
    systemctl restart xray >> $LOG_FILE 2>&1
    
    # Generate client info
    generate_client_info
    generate_qr_code
    
    # Show completion message
    echo -e "${GREEN}\n[+] Xray installation completed!${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}Domain: $DOMAIN${NC}"
    echo -e "${GREEN}Protocol: $PROTOCOL${NC}"
    echo -e "${GREEN}Port: 443${NC}"
    [[ "$PROTOCOL" != "shadowsocks" ]] && echo -e "${GREEN}UUID/Password: $UUID${NC}"
    [[ "$PROTOCOL" == "vmess" || "$PROTOCOL" == "vless" ]] && echo -e "${GREEN}Path: $PATH${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "${YELLOW}Client configuration saved to: $CLIENT_INFO${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    # Show service status
    echo -e "\n${BLUE}[i] Service Status:${NC}"
    systemctl status xray --no-pager
    echo -e "\n${BLUE}[i] Nginx Status:${NC}"
    systemctl status nginx --no-pager
}

# ========================
# Main Execution
# ========================

function main() {
    initialize
    get_user_input
    setup_certificates
    install_xray
    generate_config
    configure_nginx
    configure_firewall
    finalize_installation
}

# Start the installation
main
