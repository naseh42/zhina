from pydantic import BaseModel, Field, validator
from typing import Dict, Optional, List
from pathlib import Path
from backend.config import settings
import logging
import subprocess

logger = logging.getLogger(__name__)

class XraySettings(BaseModel):
    """
    تنظیمات پیشرفته Xray Core
    
    شامل تمام پارامترهای مورد نیاز برای پیکربندی و مدیریت Xray
    """
    enable: bool = Field(
        default=True,
        description="وضعیت فعال/غیرفعال بودن سرویس Xray"
    )
    
    config_path: Path = Field(
        default=Path("/etc/xray/config.json"),
        description="مسیر کامل فایل کانفیگ Xray"
    )
    
    executable_path: Path = Field(
        default=Path("/usr/local/bin/xray"),
        description="مسیر اجرایی باینری Xray"
    )
    
    log_level: str = Field(
        default="warning",
        description="سطح لاگ‌گیری (مقادیر معتبر: debug, info, warning, error, none)",
        regex="^(debug|info|warning|error|none)$"
    )
    
    api_enabled: bool = Field(
        default=True,
        description="فعال/غیرفعال کردن API داخلی Xray"
    )
    
    api_port: int = Field(
        default=8080,
        ge=1024,
        le=65535,
        description="پورت API مدیریت Xray"
    )
    
    api_tag: str = Field(
        default="api",
        description="تگ مورد استفاده برای API در کانفیگ Xray"
    )
    
    auto_apply: bool = Field(
        default=True,
        description="اعمال خودکار تغییرات کانفیگ بدون نیاز به ریستارت دستی"
    )
    
    restart_command: List[str] = Field(
        default=["systemctl", "restart", "xray"],
        description="دستور ریستارت سرویس Xray"
    )

    @validator('config_path', 'executable_path')
    def validate_paths(cls, v: Path):
        if not v.exists():
            logger.warning(f"مسیر {v} وجود ندارد!")
        return v

    @validator('log_level')
    def validate_log_level(cls, v):
        valid_levels = ["debug", "info", "warning", "error", "none"]
        if v not in valid_levels:
            raise ValueError(f"سطح لاگ نامعتبر. باید یکی از این موارد باشد: {', '.join(valid_levels)}")
        return v

    def apply_config(self):
        """
        اعمال تغییرات کانفیگ و ریستارت سرویس Xray
        
        Returns:
            bool: True اگر عملیات موفقیت‌آمیز بود
        """
        try:
            if self.auto_apply:
                result = subprocess.run(
                    self.restart_command,
                    check=True,
                    capture_output=True,
                    text=True
                )
                if result.returncode == 0:
                    logger.info("Xray با موفقیت ریستارت شد")
                    return True
        except subprocess.CalledProcessError as e:
            logger.error(f"خطا در ریستارت Xray: {e.stderr}")
        except Exception as e:
            logger.error(f"خطای ناشناخته در اعمال تنظیمات: {str(e)}")
        return False

# نمونه Singleton از تنظیمات Xray
xray_settings = XraySettings()
