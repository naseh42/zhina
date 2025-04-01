from pydantic import BaseModel, Field, field_validator
from typing import Dict, List, Optional
from enum import Enum
from backend.config import settings
import logging
from pathlib import Path  # ADDED

logger = logging.getLogger(__name__)

class ProtocolType(str, Enum):
    VMESS = "vmess"
    VLESS = "vless"
    TROJAN = "trojan"
    SHADOWSOCKS = "shadowsocks"
    HTTP = "http"
    SOCKS = "socks"

class ProtocolSettings(BaseModel):
    """
    کلاس تنظیمات پروتکل‌ها با قابلیت‌های:
    - مدیریت پروتکل‌های موجود
    - تنظیمات اختصاصی هر پروتکل
    - تغییر پروتکل پیش‌فرض
    """
    available_protocols: List[ProtocolType] = Field(
        default=list(ProtocolType),
        description="لیست تمام پروتکل‌های پشتیبانی شده"
    )
    
    default_protocol: ProtocolType = Field(
        default=ProtocolType.VMESS,
        description="پروتکل پیش‌فرض سیستم"
    )
    
    protocol_configs: Dict[ProtocolType, Dict] = Field(
        default={
            ProtocolType.VMESS: {
                "security": "auto",
                "alterId": 64,
                "disableInsecureEncryption": True,
                "config_path": Path("/opt/xray/configs/vmess.json")  # ADDED
            },
            ProtocolType.VLESS: {
                "flow": "xtls-rprx-direct",
                "encryption": "none",
                "serviceName": settings.XRAY_PATH,
                "config_path": Path("/opt/xray/configs/vless.json")  # ADDED
            },
            ProtocolType.TROJAN: {
                "password": settings.XRAY_UUID,
                "email": f"admin@{settings.SERVER_IP}",
                "config_path": Path("/opt/xray/configs/trojan.json")  # ADDED
            },
            ProtocolType.SHADOWSOCKS: {
                "method": "aes-128-gcm",
                "password": settings.XRAY_UUID,
                "config_path": Path("/opt/xray/configs/shadowsocks.json")  # ADDED
            },
            ProtocolType.HTTP: {
                "timeout": 300,
                "allowTransparent": False,
                "config_path": Path("/opt/xray/configs/http.json")  # ADDED
            },
            ProtocolType.SOCKS: {
                "auth": "noauth",
                "udp": True,
                "config_path": Path("/opt/xray/configs/socks.json")  # ADDED
            }
        },
        description="تنظیمات اختصاصی هر پروتکل"
    )

    @field_validator('default_protocol')
    @classmethod
    def validate_default_protocol(cls, v):
        if v not in cls.model_fields['available_protocols'].default:
            raise ValueError("پروتکل پیش‌فرض باید در لیست پروتکل‌های موجود باشد")
        return v

    def get_protocol_config(self, protocol: ProtocolType) -> Dict:
        """
        دریافت تنظیمات کامل یک پروتکل
        
        Args:
            protocol: نوع پروتکل (از enum ProtocolType)
            
        Returns:
            Dict: تنظیمات پروتکل مورد نظر
            
        Raises:
            ValueError: اگر پروتکل معتبر نباشد
        """
        if protocol not in self.available_protocols:
            logger.error(f"پروتکل نامعتبر درخواست شده: {protocol}")
            raise ValueError("پروتکل مورد نظر پشتیبانی نمی‌شود")
            
        return self.protocol_configs.get(protocol, {})

    def set_default_protocol(self, protocol: ProtocolType):
        """
        تغییر پروتکل پیش‌فرض سیستم
        
        Args:
            protocol: پروتکل جدید (از enum ProtocolType)
            
        Raises:
            ValueError: اگر پروتکل معتبر نباشد
        """
        if protocol not in self.available_protocols:
            logger.error(f"تلاش برای تنظیم پروتکل نامعتبر به عنوان پیش‌فرض: {protocol}")
            raise ValueError("پروتکل معتبر نیست")
            
        self.default_protocol = protocol
        logger.info(f"پروتکل پیش‌فرض به {protocol} تغییر یافت")

    def get_all_configs(self) -> Dict[ProtocolType, Dict]:
        """دریافت تمام تنظیمات پروتکل‌ها به صورت دیکشنری"""
        return self.protocol_configs

# نمونه Singleton از تنظیمات پروتکل‌ها
protocol_settings = ProtocolSettings()

# ============ توابع اضافه شده ============
def get_protocol_config(protocol_name: str) -> dict:  # ADDED
    """
    دریافت تنظیمات پروتکل به صورت تابع مستقل
    Args:
        protocol_name: نام پروتکل (vmess, vless, ...)
    Returns:
        dict: تنظیمات مربوط به پروتکل
    Raises:
        ValueError: اگر نام پروتکل نامعتبر باشد
    """
    try:
        protocol = ProtocolType(protocol_name.lower())
        return protocol_settings.get_protocol_config(protocol)
    except ValueError as e:
        logger.error(f"Invalid protocol requested: {protocol_name}")
        raise ValueError("پروتکل مورد نظر پشتیبانی نمی‌شود") from e

def set_default_protocol(protocol_name: str) -> None:  # ADDED
    """
    تنظیم پروتکل پیش‌فرض به صورت تابع مستقل
    Args:
        protocol_name: نام پروتکل (vmess, vless, ...)
    Raises:
        ValueError: اگر نام پروتکل نامعتبر باشد
    """
    try:
        protocol = ProtocolType(protocol_name.lower())
        protocol_settings.set_default_protocol(protocol)
    except ValueError as e:
        logger.error(f"Attempt to set invalid default protocol: {protocol_name}")
        raise ValueError("پروتکل معتبر نیست") from e

def validate_protocol_config(config: dict) -> bool:  # ADDED
    """
    اعتبارسنجی تنظیمات پروتکل
    Args:
        config: دیکشنری تنظیمات
    Returns:
        bool: True اگر تنظیمات معتبر باشد
    """
    required_fields = {
        ProtocolType.VMESS: ["security", "alterId"],
        ProtocolType.VLESS: ["flow", "encryption"],
        ProtocolType.TROJAN: ["password"],
        ProtocolType.SHADOWSOCKS: ["method", "password"]
    }
    
    protocol_type = config.get("protocol")
    if not protocol_type:
        return False
        
    try:
        protocol = ProtocolType(protocol_type)
        return all(field in config for field in required_fields.get(protocol, []))
    except ValueError:
        return False
