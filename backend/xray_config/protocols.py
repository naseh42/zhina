from pydantic import BaseModel
from typing import Dict, List, Optional

class ProtocolSettings(BaseModel):
    available_protocols: List[str] = [
        "vmess", "vless", "trojan", "shadowsocks", "http", "socks"
    ]
    default_protocol: str = "vmess"
    protocol_configs: Dict[str, Dict] = {
        "vmess": {
            "security": "auto",
            "alterId": 64
        },
        "vless": {
            "flow": "xtls-rprx-direct",
            "encryption": "none"
        },
        "trojan": {
            "password": "your_password"
        },
        "shadowsocks": {
            "method": "aes-128-gcm",
            "password": "your_password"
        },
        "http": {
            "timeout": 300
        },
        "socks": {
            "auth": "noauth"
        }
    }

    def get_protocol_config(self, protocol: str) -> Optional[Dict]:
        """ دریافت تنظیمات پیش‌فرض برای یک پروتکل """
        return self.protocol_configs.get(protocol)

    def set_default_protocol(self, protocol: str):
        """ تنظیم پروتکل پیش‌فرض """
        if protocol in self.available_protocols:
            self.default_protocol = protocol
        else:
            raise ValueError("پروتکل معتبر نیست.")

protocol_settings = ProtocolSettings()
