from pydantic_settings import BaseSettings
from pydantic import Field, field_validator, HttpUrl, EmailStr
from typing import Optional, Literal
import os
import secrets
import warnings
import uuid
from pathlib import Path
from dotenv import load_dotenv
load_dotenv("/var/lib/zhina/backend/.env")
print("SECRET_KEY:", os.getenv("ZHINA_SECRET_KEY"))

class Settings(BaseSettings):
    # 1. Database Configuration
    DATABASE_URL: str = Field(
        default="postgresql://zhina_user:1b4becba55eab852259f6b0051414ace@localhost:5432/zhina_db",
        description="Database connection URL in SQLAlchemy format",
        example="postgresql://user:password@localhost:5432/dbname"
    )
    
    # 2. Xray Core Settings
    XRAY_UUID: str = Field(
        default_factory=lambda: str(uuid.uuid4()),
        min_length=36,
        max_length=36,
        description="Main UUID for Xray connections"
    )
    XRAY_PATH: str = Field(
        default_factory=lambda: f"/{secrets.token_hex(8)}",
        description="Base path for Xray connections",
        pattern=r'^/[a-zA-Z0-9]{16}$'
    )
    XRAY_CONFIG_PATH: Path = Field(
        default=Path("/etc/xray/config.json"),
        description="Absolute path to Xray config file"
    )
    
    # 3. Reality Protocol Settings
    REALITY_PUBLIC_KEY: str = Field(
        ...,
        min_length=43,
        max_length=43,
        description="Public key for Reality protocol",
        pattern=r'^[A-Za-z0-9-_]{43}$'
    )
    REALITY_PRIVATE_KEY: str = Field(
        ...,
        min_length=43,
        max_length=43,
        description="Private key for Reality protocol",
        pattern=r'^[A-Za-z0-9-_]{43}$'
    )
    REALITY_SHORT_ID: str = Field(
        default_factory=lambda: secrets.token_hex(8),
        min_length=16,
        max_length=16,
        description="Short ID for Reality protocol"
    )
    
   # 4. Security Settings
    SECRET_KEY: str = os.getenv(
        "ZHINA_SECRET_KEY", 
        "default_fallback_key"
    )
    DEBUG: bool = Field(
        default=False,
        description="Debug mode (DO NOT enable in production)"
    )
    
    # 5. JWT Authentication
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(
        default=30,
        ge=5,
        le=1440,
        description="Access token expiration time in minutes"
    )
    
    # 5. JWT Authentication
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(
        default=30,
        ge=5,
        le=1440,
        description="Access token expiration time in minutes"
    )
    
    # 5. JWT Authentication
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(
        default=30,
        ge=5,
        le=1440,
        description="Access token expiration time in minutes"
    )
    JWT_ALGORITHM: Literal["HS256", "HS384", "HS512"] = Field(
        default="HS256",
        description="JWT signing algorithm"
    )
    
    # 6. Admin Account
    ADMIN_USERNAME: str = Field(
        default="admin",
        min_length=4,
        max_length=32,
        description="Default admin username"
    )
    ADMIN_PASSWORD: str = Field(
        default="ChangeMe123!",
        min_length=12,
        description="Default admin password"
    )
    ADMIN_EMAIL: EmailStr = Field(
        default="admin@example.com",
        description="Admin contact email"
    )
    
    # 7. Panel Configuration
    LANGUAGE: Literal["fa", "en"] = Field(
        default="fa",
        description="Panel interface language"
    )
    THEME: Literal["dark", "light", "auto"] = Field(
        default="dark",
        description="UI color theme"
    )
    ENABLE_NOTIFICATIONS: bool = Field(
        default=True,
        description="Enable system notifications"
    )
    
    # 8. Server Network
    SERVER_IP: Optional[str] = Field(
        default=None,
        description="Public IP address for the server"
    )
    SERVER_PORT: int = Field(
        default=8001,
        ge=1024,
        le=65535,
        description="Panel service port (1024-65535)"
    )
    SERVER_HOST: str = Field(
        default="0.0.0.0",
        description="Host interface to bind to"
    )
    
    # 9. SSL Configuration
    SSL_CERT_PATH: Optional[Path] = Field(
        default=None,
        description="Path to SSL certificate file"
    )
    SSL_KEY_PATH: Optional[Path] = Field(
        default=None,
        description="Path to SSL private key file"
    )
    
    # 10. Rate Limiting
    RATE_LIMIT: int = Field(
        default=100,
        ge=10,
        description="Requests per minute per IP"
    )

    model_config = {
        "env_file": "/var/lib/zhina/backend/.env",
        "env_file_encoding": "utf-8",
        "extra": "forbid",
        "env_prefix": "ZHINA_",
        "secrets_dir": "/etc/zhina/secrets"
    }

    @field_validator("DATABASE_URL")
    @classmethod
    def validate_db_url(cls, v: str) -> str:
        if "postgres:" in v:
            raise ValueError("Use postgresql:// instead of postgres://")
        if "sqlite:" in v and not v.startswith("sqlite:///"):
            raise ValueError("SQLite requires absolute path (sqlite:////path/to/db)")
        return v

    @field_validator("ADMIN_PASSWORD")
    @classmethod
    def validate_admin_password(cls, v: str) -> str:
        if v == "ChangeMe123!":
            warnings.warn("Default admin password detected! Please change immediately.", UserWarning)
        if len(v) < 12:
            raise ValueError("Password must be at least 12 characters")
        return v

    @field_validator("DEBUG")
    @classmethod
    def validate_debug(cls, v: bool, info) -> bool:
        if v and info.data.get("SERVER_HOST") == "0.0.0.0":
            warnings.warn("Debug mode is enabled with public host binding!", RuntimeWarning)
        return v

    @field_validator("SSL_CERT_PATH", "SSL_KEY_PATH")
    @classmethod
    def validate_ssl_paths(cls, v: Optional[Path], info) -> Optional[Path]:
        if v and not v.exists():
            raise ValueError(f"{info.field_name} path does not exist: {v}")
        return v

settings = Settings()
