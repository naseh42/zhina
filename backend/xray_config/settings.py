from pydantic import BaseModel, Field
from typing import Dict, Optional

class XraySettings(BaseModel):
    """
    تنظیمات اصلی Xray Core
    """
    enable: bool = Field(
        default=True,
        description="فعال/غیرفعال کردن سرویس Xray"
    )
    config_path: str = Field(
        default="/etc/xray/config.json",
        description="مسیر فایل پیکربندی Xray"
    )
    executable_path: str = Field(
        default="/usr/local/bin/xray/xray",
        description="مسیر اجرایی Xray"
    )
    log_level: str = Field(
        default="warning",
        description="سطح لاگ‌گیری (debug, info, warning, error, none)"
    )
    api_enabled: bool = Field(
        default=True,
        description="فعال کردن API مدیریت Xray"
    )
    api_port: int = Field(
        default=8080,
        description="پورت API مدیریت Xray"
    )
    api_tag: str = Field(
        default="api",
        description="تگ برای API مدیریت"
    )

    class Config:
        env_file = ".env"
        env_prefix = "XRAY_"

xray_settings = XraySettings()
