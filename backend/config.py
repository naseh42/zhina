from pydantic_settings import BaseSettings
from pydantic import Field, validator
import os
from typing import Optional

class Settings(BaseSettings):
    # تنظیمات دیتابیس (الزامی)
    DATABASE_URL: str = Field(
        default="sqlite:///./zhina.db",
        description="URL اتصال به دیتابیس (پستگرس: postgresql://user:pass@localhost/dbname)"
    )
    
    # تنظیمات Xray (الزامی)
    XRAY_UUID: str = Field(
        ...,
        min_length=36,
        max_length=36,
        description="UUID اصلی برای اتصالات Xray"
    )
    XRAY_PATH: str = Field(
        default="/xray",
        description="مسیر پایه برای اتصالات Xray"
    )
    XRAY_CONFIG_PATH: str = Field(
        default="/etc/xray/config.json",
        description="مسیر ذخیره فایل کانفیگ Xray"
    )
    
    # تنظیمات Reality (الزامی)
    REALITY_PUBLIC_KEY: str = Field(
        ...,
        min_length=43,
        max_length=43,
        description="کلید عمومی برای پروتکل Reality"
    )
    REALITY_SHORT_ID: str = Field(
        ...,
        min_length=16,
        max_length=16,
        description="شناسه کوتاه برای Reality"
    )
    
    # تنظیمات امنیتی (الزامی)
    SECRET_KEY: str = Field(
        ...,
        min_length=32,
        description="کلید امنیتی برای JWT و رمزنگاری"
    )
    DEBUG: bool = Field(
        default=False,
        description="حالت دیباگ (در تولید باید False باشد)"
    )
    
    # تنظیمات مدیریتی (اختیاری)
    ADMIN_USERNAME: str = Field(
        default="admin",
        description="نام کاربری ادمین پیشفرض"
    )
    ADMIN_PASSWORD: str = Field(
        default="ChangeMe123!",
        description="رمز عبور ادمین پیشفرض (باید در اولین ورود تغییر کند)"
    )
    
    # تنظیمات ظاهری (اختیاری)
    LANGUAGE: str = Field(
        default="fa",
        description="زبان پیشفرض پنل (fa/en)"
    )
    THEME: str = Field(
        default="dark",
        description="تم پیشفرض (light/dark)"
    )
    ENABLE_NOTIFICATIONS: bool = Field(
        default=True,
        description="اعلان‌های سیستم فعال باشد؟"
    )

    # تنظیمات سرور (اختیاری)
    SERVER_IP: Optional[str] = Field(
        default=None,
        description="IP سرور (اگر خالی باشد به صورت خودکار تشخیص داده می‌شود)"
    )
    SERVER_PORT: int = Field(
        default=8000,
        ge=1,
        le=65535,
        description="پورت اجرای پنل مدیریتی"
    )

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"
        case_sensitive = True

    @validator("DATABASE_URL")
    def validate_db_url(cls, v):
        if "postgresql" in v and "postgres:" in v:
            raise ValueError("برای امنیت بیشتر از postgresql:// به جای postgres:// استفاده کنید")
        return v

    @validator("ADMIN_PASSWORD")
    def validate_admin_password(cls, v):
        if v == "ChangeMe123!":
            import warnings
            warnings.warn("رمز عبور پیشفرض ادمین تغییر نکرده است! این یک ریسک امنیتی است.")
        return v

settings = Settings()
