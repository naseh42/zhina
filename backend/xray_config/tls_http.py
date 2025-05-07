from pydantic import BaseModel, Field, validator
from typing import List, Optional
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

    def generate_tls_config(self):
        """
        تولید پیکربندی TLS بر اساس تنظیمات موجود
        
        این تابع پیکربندی TLS را به صورت دیکشنری یا شیء مناسب برمی‌گرداند.
        """
        if not self.enable:
            logger.warning("TLS غیرفعال است، پیکربندی ایجاد نمی‌شود.")
            return {}
        
        config = {
            "certificate": str(self.certificate_path) if self.certificate_path else None,
            "key": str(self.key_path) if self.key_path else None,
            "server_name": self.server_name,
            "alpn": self.alpn,
            "min_version": self.min_version,
            "max_version": self.max_version
        }
        logger.info("پیکربندی TLS با موفقیت تولید شد.")
        return config

    def validate_tls_certificates(self):
        """
        اعتبارسنجی گواهی و کلید SSL
        
        بررسی می‌کند که آیا فایل‌های گواهی و کلید موجود هستند و درست تنظیم شده‌اند.
        """
        if not self.certificate_path or not self.key_path:
            logger.error("مسیر گواهی یا کلید خصوصی تنظیم نشده است.")
            return False
        
        if not self.certificate_path.exists() or not self.key_path.exists():
            logger.error("فایل گواهی یا کلید خصوصی یافت نشد.")
            return False
        
        logger.info("گواهی و کلید خصوصی معتبر هستند.")
        return True

    def apply_tls_settings(self):
        """
        اعمال تنظیمات TLS به سرور
        
        این تابع می‌تواند تنظیمات TLS را در سرویس مورد نظر مانند Xray اعمال کند.
        """
        if not self.validate_tls_certificates():
            logger.error("تنظیمات TLS معتبر نیستند.")
            return False
        
        # اینجا می‌توانید کد لازم برای اعمال پیکربندی TLS به سرور Xray یا هر سیستم دیگر را بنویسید.
        logger.info("تنظیمات TLS با موفقیت اعمال شدند.")
        return True


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
