from pydantic_settings import BaseSettings
from pydantic import Field, field_validator, HttpUrl, EmailStr
from typing import Optional, Literal
import os
import secrets
import warnings
import uuid
from pathlib import Path
from dotenv import load_dotenv

load_dotenv("/opt/zhina/backend/.env")

class Settings(BaseSettings):
    # Database Configuration
    DATABASE_URL: str = Field(
        default="postgresql://zhina_user:1b4becba55eab852259f6b0051414ace@localhost:5432/zhina_db",
        examples=["postgresql://user:password@localhost:5432/dbname"]
    )
    
    # Xray Core Configuration
    XRAY_UUID: str = Field(
        default_factory=lambda: str(uuid.uuid4()),
        min_length=36,
        max_length=36
    )
    
    XRAY_PATH: str = Field(
        default_factory=lambda: f"/{secrets.token_hex(8)}",
        pattern=r'^/[a-zA-Z0-9]{16}$'
    )
    
    XRAY_CONFIG_PATH: Path = Field(
        default=Path("/etc/xray/config.json")
    )
    
    # Reality Keys
    REALITY_PUBLIC_KEY: str = Field(
        ...,
        min_length=43,
        max_length=43,
        pattern=r'^[A-Za-z0-9-_]{43}$'
    )
    
    REALITY_PRIVATE_KEY: str = Field(
        ...,
        min_length=43,
        max_length=43,
        pattern=r'^[A-Za-z0-9-_]{43}$'
    )
    
    REALITY_SHORT_ID: str = Field(
        default_factory=lambda: secrets.token_hex(8),
        min_length=16,
        max_length=16
    )
    
    # Xray Additional Settings
    XRAY_HTTP_PORT: int = Field(
        default=8080,
        ge=1024,
        le=65535
    )
    
    # Security Settings
    SECRET_KEY: str = Field(
        default=secrets.token_urlsafe(32),
        min_length=32
    )
    
    DEBUG: bool = Field(default=False)
    
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(
        default=30,
        ge=5,
        le=1440
    )
    
    JWT_ALGORITHM: Literal["HS256", "HS384", "HS512"] = Field(default="HS256")
    
    # Admin Configuration
    ADMIN_USERNAME: str = Field(
        default="admin",
        min_length=4,
        max_length=32
    )
    
    ADMIN_PASSWORD: str = Field(
        default="ChangeMe123!",
        min_length=12
    )
    
    ADMIN_EMAIL: EmailStr = Field(default="admin@example.com")
    
    # Panel Configuration
    PANEL_PORT: int = Field(
        default=8001,
        ge=1024,
        le=65535
    )
    
    PANEL_DOMAIN: str = Field(
        default="localhost"
    )
    
    # UI Configuration
    LANGUAGE: Literal["fa", "en"] = Field(default="fa")
    
    DEFAULT_THEME: Literal["dark", "light", "auto"] = Field(default="dark")
    
    ENABLE_NOTIFICATIONS: bool = Field(default=True)
    
    # Server Configuration
    SERVER_IP: Optional[str] = Field(default=None)
    
    SERVER_PORT: int = Field(
        default=8001,
        ge=1024,
        le=65535
    )
    
    SERVER_HOST: str = Field(default="0.0.0.0")
    
    SSL_CERT_PATH: Optional[Path] = Field(default=None)
    
    SSL_KEY_PATH: Optional[Path] = Field(default=None)
    
    # Rate Limiting
    RATE_LIMIT: int = Field(
        default=100,
        ge=10
    )
    
    # Xray Sync Interval
    XRAY_SYNC_INTERVAL: int = Field(
        default=300,
        ge=60,
        description="Sync interval in seconds"
    )

    class Config:
        env_file = "/opt/zhina/backend/.env"
        env_file_encoding = 'utf-8'
        extra = 'ignore'  # تغییر از 'forbid' به 'ignore' برای جلوگیری از خطا

    @field_validator("DATABASE_URL")
    @classmethod
    def validate_db_url(cls, v: str) -> str:
        if "postgres:" in v:
            raise ValueError("Use postgresql:// instead of postgres://")
        return v

    @field_validator("ADMIN_PASSWORD")
    @classmethod
    def validate_admin_password(cls, v: str) -> str:
        if v == "ChangeMe123!":
            warnings.warn("Default admin password detected! Please change it immediately.", UserWarning)
        return v

settings = Settings()
