from pydantic import BaseModel, Field, validator
from typing import Dict, List, Optional
from enum import Enum
from backend.config import settings
import logging

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
    تنظیمات پیشرفته پروتکل‌های شبکه
    
    شامل:
    - لیست پروتکل‌های قابل استفاده
    - تنظیمات پیش‌فرض هر پروتکل
    - متدهای مدیریت پروتکل‌ها
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
                "disableInsecureEncryption": True
            },
            ProtocolType.VLESS: {
                "flow": "xtls-rprx-direct",
                "encryption": "none",
                "serviceName": settings.XRAY_PATH
            },
            ProtocolType.TROJAN: {
                "password": settings.XRAY_UUID,
                "email": f"admin@{settings.SERVER_IP}"
            },
            ProtocolType.SHADOWSOCKS: {
                "method": "aes-128-gcm",
                "password": settings.XRAY_UUID
            },
            ProtocolType.HTTP: {
                "timeout": 300,
                "allowTransparent": False
            },
            ProtocolType.SOCKS: {
                "auth": "noauth",
                "udp": True
            }
        },
        description="تنظیمات اختصاصی هر پروتکل"
    )

    @validator('default_protocol')
    def validate_default_protocol(cls, v):
        if v not in cls.available_protocols:
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

# نمونه singleton از تنظیمات پروتکل‌ها
protocol_settings = ProtocolSettings()
