from pydantic_settings import BaseSettings
from pydantic import Field, field_validator, HttpUrl, EmailStr
from typing import Optional, Literal
import os
import secrets
import warnings
import uuid
from pathlib import Path
from dotenv import load_dotenv

# تغییر مسیر بارگذاری env به مسیر نسبی
load_dotenv(Path(__file__).parent.parent / ".env")

class Settings(BaseSettings):
    # 1. Database - اصلاح برای تطابق با FastAPI شما
    DATABASE_URL: str = Field(
        default="postgresql://zhina_user:1b4becba55eab852259f6b0051414ace@localhost:5432/zhina_db",
        env="DATABASE_URL"  # اضافه شد
    )
    
    # 2. Xray - اضافه کردن تنظیمات جدید
    XRAY_EXECUTABLE_PATH: Path = Field(
        default=Path("/usr/bin/xray"),
        description="Path to Xray binary"
    )
    
    # 3. Security - یکپارچه‌سازی با FastAPI شما
    SECRET_KEY: str = Field(
        default=os.getenv("ZHINA_SECRET_KEY", "default_fallback_key"),
        min_length=32,
        description="Secret key for JWT tokens"
    )
    
    # 4. JWT - هماهنگ با کد FastAPI شما
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(
        default=30,
        description="Matches your FastAPI token expiry"
    )
    
    # 5. Panel - اضافه کردن تنظیمات تمپلیت
    TEMPLATE_DIR: Path = Field(
        default=Path("/var/lib/zhina/frontend/templates"),
        description="Jinja2 templates directory"
    )
    
    # حذف تنظیمات تکراری (ACCESS_TOKEN_EXPIRE_MINUTES که سه بار تکرار شده بود)
    
    model_config = {
        "env_file": ".env",  # تغییر به مسیر نسبی
        "extra": "ignore",  # تغییر از forbid به ignore برای انعطاف بیشتر
    }

    @field_validator("DATABASE_URL")
    @classmethod
    def validate_db_url(cls, v: str) -> str:
        if "postgres:" in v:
            v = v.replace("postgres:", "postgresql:")
        return v

    @field_validator("SECRET_KEY")
    @classmethod
    def validate_secret_key(cls, v: str) -> str:
        if v == "default_fallback_key":
            warnings.warn("Using default secret key is insecure!", UserWarning)
        return v

settings = Settings()
