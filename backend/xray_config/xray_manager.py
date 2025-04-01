import json
import subprocess
import logging
from typing import Dict, List, Optional, Any
from pathlib import Path
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from functools import wraps

from .inbounds import get_inbounds, create_inbound
from .protocols import protocol_settings
from .settings import xray_settings
from .subscription import create_subscription, get_subscription
from .tls_http import tls_settings
from backend.models import Inbound, User
from backend.config import settings
from backend.utils import generate_uuid
from backend.database import SessionLocal

logger = logging.getLogger(__name__)

class XrayManager:
    """
    مدیریت کامل سرویس Xray شامل:
    - ایجاد/حذف کاربران
    - مدیریت اینباندها
    - به‌روزرسانی کانفیگ
    - کنترل سرویس
    """

    def __init__(self, db: Session):
        self.db = db
        self.config_path = Path("/etc/xray/config.json")
        self.backup_path = Path("/etc/xray/config.json.bak")

    def update_xray_config(self) -> bool:
        """به‌روزرسانی پیکربندی Xray"""
        try:
            # 1. جمع‌آوری تمام اینباندهای فعال
            active_inbounds = [
                inbound.to_config_dict() 
                for inbound in get_inbounds(self.db)
                if inbound.is_active
            ]

            # 2. ساخت ساختار کانفیگ نهایی
            config = {
                "log": {
                    "loglevel": xray_settings.log_level
                },
                "inbounds": active_inbounds,
                "outbounds": [
                    {
                        "protocol": "freedom",
                        "tag": "direct"
                    }
                ],
                "routing": {
                    "domainStrategy": "AsIs",
                    "rules": []
                }
            }

            # 3. ایجاد پشتیبان
            self._create_backup()

            # 4. ذخیره فایل کانفیگ
            with open(self.config_path, 'w') as f:
                json.dump(config, f, indent=4, ensure_ascii=False)

            # 5. ریستارت سرویس (با بررسی وجود ویژگی restart_on_update)
            if hasattr(xray_settings, 'restart_on_update') and xray_settings.restart_on_update:
                return self.restart_service()
            
            logger.info("Xray config updated successfully")
            return True

        except Exception as e:
            logger.error(f"Failed to update Xray config: {str(e)}")
            return False

    def _create_backup(self) -> None:
        """ایجاد پشتیبان از فایل پیکربندی"""
        if self.config_path.exists():
            with open(self.config_path, 'r') as src, open(self.backup_path, 'w') as dst:
                dst.write(src.read())

    def restart_service(self) -> bool:
        """ریستارت سرویس Xray"""
        try:
            result = subprocess.run(
                ["systemctl", "restart", "xray"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            logger.info(f"Xray restarted: {result.stdout}")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Xray restart failed: {e.stderr}")
            return False

    def get_config(self) -> Dict[str, Any]:
        """دریافت پیکربندی فعلی"""
        try:
            with open(self.config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to get Xray config: {str(e)}")
            return {}

    def add_user(self, user_id: int, protocol: str = None) -> Dict:
        """ایجاد کاربر جدید در Xray"""
        try:
            protocol = protocol or protocol_settings.default_protocol
            uuid = generate_uuid()
            
            sub_data = {
                "uuid": uuid,
                "user_id": user_id,
                "data_limit": settings.DEFAULT_DATA_LIMIT,
                "expiry_date": (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d"),
                "max_connections": settings.DEFAULT_MAX_CONNECTIONS
            }
            subscription = create_subscription(self.db, sub_data)

            inbound_config = self._generate_inbound_config(protocol, uuid)
            inbound = create_inbound(self.db, inbound_config)

            # اضافه کردن بررسی وجود ویژگی auto_apply
            if hasattr(xray_settings, 'auto_apply') and xray_settings.auto_apply:
                self.update_xray_config()

            sub_link = self.generate_subscription_link(uuid, protocol)

            return {
                "status": "success",
                "user_id": user_id,
                "uuid": uuid,
                "protocol": protocol,
                "subscription_link": sub_link,
                "config": inbound_config
            }
        except Exception as e:
            logger.error(f"Error adding user: {str(e)}")
            raise

    def _generate_inbound_config(self, protocol: str, uuid: str) -> Dict:
        """تولید کانفیگ اینباند"""
        base_config = {
            "port": settings.XRAY_DEFAULT_PORT,
            "protocol": protocol,
            "tag": f"inbound-{uuid[:8]}",
            "settings": {
                "clients": [{"id": uuid}]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls" if tls_settings.enable else "none",
                "tlsSettings": tls_settings.dict() if tls_settings.enable else None
            }
        }
        
        protocol_config = protocol_settings.get_protocol_config(protocol)
        base_config["settings"].update(protocol_config)
        
        return base_config

    def generate_subscription_link(self, uuid: str, protocol: str) -> str:
        """تولید لینک اشتراک‌گذاری"""
        domain = settings.DOMAIN or getattr(xray_settings, 'server_name', 'localhost')
        base_link = f"https://{domain}/sub/{uuid}"
        
        if protocol == "vless":
            return f"vless://{uuid}@{domain}:443?security=tls&type=tcp#{uuid[:8]}"
        
        return base_link
