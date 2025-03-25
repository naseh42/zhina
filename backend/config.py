from pydantic_settings import BaseSettings
from pydantic import Field, validator
import os
from typing import Optional

class Settings(BaseSettings):
    # Database Settings
    DATABASE_URL: str = Field(
        default="sqlite:///./zhina.db",
        description="Database connection URL"
    )
    
    # Xray Settings
    XRAY_UUID: str = Field(
        ...,
        min_length=36,
        max_length=36,
        description="Xray main UUID"
    )
    XRAY_PATH: str = Field(
        default="/xray",
        description="Xray base path"
    )
    XRAY_CONFIG_PATH: str = Field(
        default="/etc/xray/config.json",
        description="Xray config file path"
    )
    
    # Reality Settings
    REALITY_PUBLIC_KEY: str = Field(
        ...,
        min_length=43,
        max_length=43,
        description="Reality public key"
    )
    REALITY_SHORT_ID: str = Field(
        ...,
        min_length=16,
        max_length=16,
        description="Reality short ID"
    )
    
    # Security Settings
    SECRET_KEY: str = Field(
        ...,
        min_length=32,
        description="Secret key for encryption"
    )
    DEBUG: bool = Field(
        default=False,
        description="Debug mode"
    )
    
    # JWT Settings
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(
        default=30,
        description="Access token expiration time"
    )
    JWT_ALGORITHM: str = Field(
        default="HS256",
        description="JWT encryption algorithm"
    )
    
    # Admin Settings
    ADMIN_USERNAME: str = Field(
        default="admin",
        description="Default admin username"
    )
    ADMIN_PASSWORD: str = Field(
        default="ChangeMe123!",
        description="Default admin password"
    )
    
    # UI Settings
    LANGUAGE: str = Field(
        default="fa",
        description="Panel language"
    )
    THEME: str = Field(
        default="dark",
        description="Panel theme"
    )
    ENABLE_NOTIFICATIONS: bool = Field(
        default=True,
        description="Enable notifications"
    )

    # Server Settings
    SERVER_IP: Optional[str] = Field(
        default=None,
        description="Server IP address"
    )
    SERVER_PORT: int = Field(
        default=8000,
        ge=1,
        le=65535,
        description="Panel port"
    )

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"
        case_sensitive = True

    @validator("DATABASE_URL")
    def validate_db_url(cls, v):
        if "postgresql" in v and "postgres:" in v:
            raise ValueError("Use postgresql:// instead of postgres:// for security")
        return v

    @validator("ADMIN_PASSWORD")
    def validate_admin_password(cls, v):
        if v == "ChangeMe123!":
            import warnings
            warnings.warn("Default admin password not changed! Security risk!")
        return v

settings = Settings()
