from pydantic import BaseModel, Field, validator
from typing import Dict, Optional, List
from pathlib import Path
from backend.config import settings
import logging
import os

logger = logging.getLogger(__name__)

class TLSSettings(BaseModel):
    """
    تنظیمات پیشرفته TLS/SSL برای Xray
    
    شامل تمام پارامترهای مورد نیاز برای پیکربندی امنیت لایه انتقال
    """
    enable: bool = Field(
        default=True,
        description="فعال/غیرفعال کردن TLS"
    )
    
    certificate_path: Optional[Path] = Field(
        default=None,
        description="مسیر کامل فایل گواهی SSL"
    )
    
    key_path: Optional[Path] = Field(
        default=None,
        description="مسیر کامل فایل کلید خصوصی"
    )
    
    server_name: str = Field(
        default=settings.SERVER_IP if settings.SERVER_IP else "example.com",
        description="نام سرور برای گواهی SSL"
    )
    
    alpn: List[str] = Field(
        default=["h2", "http/1.1"],
        description="لیست پروتکل‌های ALPN"
    )
    
    min_version: str = Field(
        default="1.2",
        description="حداقل نسخه TLS (1.2 یا 1.3)"
    )
    
    max_version: str = Field(
        default="1.3",
        description="حداکثر نسخه TLS (1.2 یا 1.3)"
    )
    
    @validator('certificate_path', 'key_path')
    def validate_paths(cls, v):
        if v is not None and not v.exists():
            logger.warning(f"فایل {v} یافت نشد!")
        return v
    
    @validator('min_version', 'max_version')
    def validate_tls_versions(cls, v):
        if v not in ["1.2", "1.3"]:
            raise ValueError("نسخه TLS باید 1.2 یا 1.3 باشد")
        return v
    
    def set_certificate(self, cert_path: str, key_path: str):
        """
        تنظیم مسیرهای گواهی SSL
        
        Args:
            cert_path: مسیر فایل گواهی
            key_path: مسیر فایل کلید خصوصی
        """
        self.certificate_path = Path(cert_path)
        self.key_path = Path(key_path)
        logger.info("مسیرهای گواهی TLS با موفقیت تنظیم شدند")

class HTTPSettings(BaseModel):
    """
    تنظیمات پروتکل HTTP
    
    شامل پارامترهای پیکربندی برای ترافیک HTTP
    """
    enable: bool = Field(
        default=True,
        description="فعال/غیرفعال کردن پروتکل HTTP"
    )
    
    timeout: int = Field(
        default=300,
        ge=30,
        le=600,
        description="زمان تایم‌اوت اتصال بر حسب ثانیه"
    )
    
    allow_transparent: bool = Field(
        default=False,
        description="اجازه ترافیک شفاف پروکسی"
    )
    
    redirect_url: Optional[str] = Field(
        default=None,
        description="URL برای ریدایرکت در صورت نیاز"
    )

# نمونه‌های Singleton از تنظیمات
tls_settings = TLSSettings()
http_settings = HTTPSettings()
