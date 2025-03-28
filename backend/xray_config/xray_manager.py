from .inbounds import create_inbound, update_inbound
from .protocol import protocol_settings
from .settings import xray_settings
from .subscription import create_subscription
import subprocess
import json

class XrayManager:
    def __init__(self, db):
        self.db = db
    
    def add_user(self, user_data):
        """مراحل کامل اضافه کردن کاربر"""
        # 1. ساخت سابسکریپشن
        sub = create_subscription(self.db, user_data)
        
        # 2. ساخت اینباند
        inbound_data = {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": user_data.uuid}]
            }
        }
        create_inbound(self.db, inbound_data)
        
        # 3. آپدیت فایل Xray
        self.update_xray_config()
        
        # 4. ساخت لینک اشتراک‌گذاری
        return self.generate_sub_link(user_data.uuid)

    def update_xray_config(self):
        """آپدیت فایل config.json"""
        config = {
            "inbounds": self.get_active_inbounds(),
            "outbounds": [...]
        }
        
        with open(xray_settings.config_path, "w") as f:
            json.dump(config, f, indent=4)
        
        subprocess.run(["systemctl", "restart", "xray"])

    def get_active_inbounds(self):
        """گرفتن لیست اینباندهای فعال از دیتابیس"""
        # اینجا از دیتابیس می‌خونیم
        return [...]
