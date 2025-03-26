#!/bin/bash
# ===============================================
# نام اسکریپت: نصب کامل Zhina Panel + Xray-core با پیکربندی Reality
# نسخه: 4.3.0
# ===============================================

# ... [همان بخش‌های قبلی تا setup_xray] ...

# ----------------------------
# بخش 8: نصب و پیکربندی Xray-core با Reality کامل
# ----------------------------
setup_xray() {
    info "نصب و پیکربندی Xray با تنظیمات Reality..."
    
    # توقف سرویس قبلی
    systemctl stop xray 2>/dev/null || true
    rm -rf "$XRAY_DIR"/*
    mkdir -p "$XRAY_DIR"

    # دانلود Xray
    if ! wget "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" -O /tmp/xray.zip; then
        error "خطا در دانلود Xray"
    fi
    unzip -o /tmp/xray.zip -d "$XRAY_DIR" || error "خطا در استخراج Xray"
    chmod +x "$XRAY_EXECUTABLE"

    # تولید کلیدهای Reality
    REALITY_KEYS=$("$XRAY_EXECUTABLE" x25519)
    REALITY_PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/Private key:/ {print $3}')
    REALITY_PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Public key:/ {print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)
    REALITY_DEST="www.datadoghq.com:443"  # بهترین سایت برای Reality
    REALITY_SERVER_NAMES='["www.datadoghq.com","www.lovelive.jp"]'  # دامنه‌های معتبر

    # ایجاد کانفیگ Xray با تنظیمات Reality پیشرفته
    cat > "$XRAY_CONFIG" <<EOF
{
    "log": {
        "loglevel": "warning",
        "access": "$LOG_DIR/xray-access.log",
        "error": "$LOG_DIR/xray-error.log"
    },
    "inbounds": [
        {
            "port": $XRAY_PORT,
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
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$REALITY_DEST",
                    "xver": 0,
                    "serverNames": $REALITY_SERVER_NAMES,
                    "privateKey": "$REALITY_PRIVATE_KEY",
                    "shortIds": ["$REALITY_SHORT_ID"],
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "fingerprint": "chrome"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http","tls"]
            }
        },
        {
            "port": $XRAY_HTTP_PORT,
            "protocol": "vmess",
            "settings": {
                "clients": [{"id": "$XRAY_UUID"}]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "$XRAY_PATH"
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
            "tag": "blocked"
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

    # ایجاد سرویس systemd
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://xtls.github.io
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_EXECUTABLE run -config $XRAY_CONFIG
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray
    
    # بررسی وضعیت سرویس
    if ! systemctl is-active --quiet xray; then
        journalctl -u xray -n 50 --no-pager
        error "سرویس Xray راه‌اندازی نشد"
    fi
    
    success "Xray با تنظیمات Reality با موفقیت نصب شد"
}

# ... [ادامه اسکریپت] ...

# ----------------------------
# بخش 14: نمایش اطلاعات نصب (بهبود یافته)
# ----------------------------
show_installation_info() {
    local public_ip=$(curl -s ifconfig.me)
    local panel_url="http://${public_ip}:${PANEL_PORT}"
    
    if [[ -f "/etc/letsencrypt/live/$(hostname)/fullchain.pem" ]]; then
        panel_url="https://$(hostname)"
    elif [[ -f "/etc/nginx/ssl/fullchain.pem" ]]; then
        panel_url="https://${public_ip}"
    fi

    echo -e "\n${GREEN}=== نصب با موفقیت کامل شد ===${NC}\n"
    echo -e "${BLUE}🔗 دسترسی به پنل مدیریتی:${NC}"
    echo -e "  • ${YELLOW}${panel_url}${NC}"
    
    echo -e "\n${BLUE}🔑 مشخصات ادمین:${NC}"
    echo -e "  • یوزرنیم: ${YELLOW}${ADMIN_USER}${NC}"
    echo -e "  • رمز عبور: ${YELLOW}${ADMIN_PASS}${NC}"

    echo -e "\n${BLUE}🚀 تنظیمات Xray Reality:${NC}"
    echo -e "  • آدرس سرور: ${YELLOW}${public_ip}${NC}"
    echo -e "  • پورت: ${YELLOW}${XRAY_PORT}${NC}"
    echo -e "  • پروتکل: ${YELLOW}VLESS + Reality${NC}"
    echo -e "  • UUID: ${YELLOW}${XRAY_UUID}${NC}"
    echo -e "  • Public Key: ${YELLOW}${REALITY_PUBLIC_KEY}${NC}"
    echo -e "  • Short ID: ${YELLOW}${REALITY_SHORT_ID}${NC}"
    echo -e "  • SNI: ${YELLOW}${REALITY_DEST}${NC}"
    echo -e "  • Fingerprint: ${YELLOW}chrome${NC}"

    echo -e "\n${BLUE}🔧 دستورات مدیریتی:${NC}"
    echo -e "  • وضعیت سرویس‌ها: ${YELLOW}systemctl status zhina-panel xray nginx${NC}"
    echo -e "  • راه‌اندازی مجدد: ${YELLOW}systemctl restart xray${NC}"
    echo -e "  • مشاهده لاگ: ${YELLOW}journalctl -u xray -f${NC}"

    echo -e "\n${RED}⚠️ نکته امنیتی:${NC}"
    echo -e "  • حتماً از کلاینت‌های سازگار با Reality استفاده کنید (مثل Xray-core 1.8.0+)"
    echo -e "  • تنظیمات را با کسی به اشتراک نگذارید!"

    # ذخیره اطلاعات در فایل
    cat > "$INSTALL_DIR/xray-reality-info.txt" <<EOF
=== Xray Reality Configuration ===
Server: ${public_ip}
Port: ${XRAY_PORT}
Protocol: VLESS + Reality
UUID: ${XRAY_UUID}
Public Key: ${REALITY_PUBLIC_KEY}
Short ID: ${REALITY_SHORT_ID}
SNI: ${REALITY_DEST}
Fingerprint: chrome
Path: ${XRAY_PATH}
EOF

    chmod 600 "$INSTALL_DIR/xray-reality-info.txt"
}

# ... [بقیه اسکریپت بدون تغییر] ...
