import json
import subprocess
import logging
from typing import Dict, List, Optional
from pathlib import Path
from datetime import datetime, timedelta
from sqlalchemy.orm import Session

from .inbounds import get_inbounds, create_inbound
from .protocols import protocol_settings
from .settings import xray_settings
from .subscription import create_subscription, get_subscription
from .tls_http import tls_settings
from backend.models import Inbound, User
from backend.config import settings
from backend.utils import generate_uuid

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

    def add_user(self, user_id: int, protocol: str = None) -> Dict:
        """
        ایجاد کاربر جدید در Xray به همراه سابسکریپشن و اینباند
        
        Args:
            user_id: آیدی کاربر در دیتابیس
            protocol: پروتکل مورد نظر (در صورت عدم انتخاب از پیش‌فرض استفاده می‌شود)
            
        Returns:
            Dict: اطلاعات کاربر شامل uuid, sub_link, config
        """
        try:
            # 1. ایجاد سابسکریپشن
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

            # 2. ایجاد اینباند
            inbound_config = self._generate_inbound_config(protocol, uuid)
            inbound = create_inbound(self.db, inbound_config)

            # 3. اعمال تغییرات در Xray
            if xray_settings.auto_apply:
                self.apply_config()

            # 4. تولید لینک اشتراک‌گذاری
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
            logger.error(f"خطا در ایجاد کاربر: {str(e)}")
            raise

    def _generate_inbound_config(self, protocol: str, uuid: str) -> Dict:
        """تولید کانفیگ اینباند بر اساس پروتکل"""
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
        
        # اضافه کردن تنظیمات خاص پروتکل
        protocol_config = protocol_settings.get_protocol_config(protocol)
        base_config["settings"].update(protocol_config)
        
        return base_config

    def apply_config(self) -> bool:
        """
        اعمال تغییرات کانفیگ و ریستارت سرویس Xray
        
        Returns:
            bool: True اگر عملیات موفقیت‌آمیز بود
        """
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

            # 3. ذخیره فایل کانفیگ
            with open(xray_settings.config_path, 'w') as f:
                json.dump(config, f, indent=4, ensure_ascii=False)

            # 4. ریستارت سرویس
            if xray_settings.restart_on_update:
                return self.restart_service()
            
            return True

        except Exception as e:
            logger.error(f"خطا در اعمال کانفیگ Xray: {str(e)}")
            return False

    def restart_service(self) -> bool:
        """
        ریستارت سرویس Xray
        
        Returns:
            bool: True اگر سرویس با موفقیت ریستارت شد
        """
        try:
            result = subprocess.run(
                xray_settings.restart_command,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            logger.info(f"Xray restarted: {result.stdout}")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"خطا در ریستارت Xray: {e.stderr}")
            return False

    def generate_subscription_link(self, uuid: str, protocol: str) -> str:
        """
        تولید لینک اشتراک‌گذاری
        
        Args:
            uuid: شناسه کاربر
            protocol: پروتکل مورد استفاده
            
        Returns:
            str: لینک نهایی
        """
        domain = settings.DOMAIN or xray_settings.server_name
        base_link = f"https://{domain}/sub/{uuid}"
        
        if protocol == "vless":
            return f"vless://{uuid}@{domain}:443?security=tls&type=tcp#{uuid[:8]}"
        
        return base_link

# نمونه Singleton از XrayManager
xray_manager = XrayManager(get_db())
