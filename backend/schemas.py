from pydantic import BaseModel, EmailStr, validator
from typing import Optional, List, Dict
from datetime import datetime

# اسکیما برای ایجاد کاربر جدید
class UserCreate(BaseModel):
    name: str
    traffic_limit: int = 0
    usage_duration: int = 0
    simultaneous_connections: int = 1

    @validator("name")
    def validate_name(cls, value):
        if len(value) < 3:
            raise ValueError("نام باید حداقل ۳ کاراکتر داشته باشد.")
        return value

    @validator("traffic_limit")
    def validate_traffic_limit(cls, value):
        if value < 0:
            raise ValueError("محدودیت ترافیک باید بزرگ‌تر یا مساوی صفر باشد.")
        return value

    @validator("usage_duration")
    def validate_usage_duration(cls, value):
        if value < 0:
            raise ValueError("مدت زمان استفاده باید بزرگ‌تر یا مساوی صفر باشد.")
        return value

    @validator("simultaneous_connections")
    def validate_simultaneous_connections(cls, value):
        if value < 1:
            raise ValueError("حداقل تعداد اتصالات هم‌زمان باید ۱ باشد.")
        return value

# اسکیما برای به‌روزرسانی کاربر
class UserUpdate(BaseModel):
    name: Optional[str] = None
    traffic_limit: Optional[int] = None
    usage_duration: Optional[int] = None
    simultaneous_connections: Optional[int] = None

# اسکیما برای ایجاد دامنه جدید
class DomainCreate(BaseModel):
    name: str
    description: Optional[str] = None
    cdn_enabled: Optional[bool] = False

    @validator("name")
    def validate_name(cls, value):
        if len(value) < 3:
            raise ValueError("نام دامنه باید حداقل ۳ کاراکتر داشته باشد.")
        return value

# اسکیما برای به‌روزرسانی دامنه
class DomainUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    cdn_enabled: Optional[bool] = None

# اسکیما برای ایجاد سابسکریپشن جدید
class SubscriptionCreate(BaseModel):
    uuid: str
    data_limit: int
    expiry_date: datetime
    max_connections: int

    @validator("data_limit")
    def validate_data_limit(cls, value):
        if value < 0:
            raise ValueError("محدودیت داده باید بزرگ‌تر یا مساوی صفر باشد.")
        return value

    @validator("max_connections")
    def validate_max_connections(cls, value):
        if value < 1:
            raise ValueError("حداقل تعداد اتصالات هم‌زمان باید ۱ باشد.")
        return value

# اسکیما برای به‌روزرسانی سابسکریپشن
class SubscriptionUpdate(BaseModel):
    data_limit: Optional[int] = None
    expiry_date: Optional[datetime] = None
    max_connections: Optional[int] = None

# اسکیما برای ایجاد نود جدید
class NodeCreate(BaseModel):
    name: str
    ip_address: str
    port: int
    protocol: str

    @validator("port")
    def validate_port(cls, value):
        if value < 1 or value > 65535:
            raise ValueError("پورت باید بین ۱ تا ۶۵۵۳۵ باشد.")
        return value

    @validator("protocol")
    def validate_protocol(cls, value):
        valid_protocols = ["vmess", "vless", "trojan", "shadowsocks", "http", "socks"]
        if value not in valid_protocols:
            raise ValueError(f"پروتکل {value} معتبر نیست.")
        return value

# اسکیما برای به‌روزرسانی نود
class NodeUpdate(BaseModel):
    name: Optional[str] = None
    ip_address: Optional[str] = None
    port: Optional[int] = None
    protocol: Optional[str] = None

# اسکیما برای تنظیمات Xray
class XraySettings(BaseModel):
    enable_tls: bool = True
    tls_certificate: Optional[str] = None
    tls_key: Optional[str] = None
    tls_settings: Dict = {
        "serverName": "example.com",
        "alpn": ["h2", "http/1.1"],
        "minVersion": "1.2",
        "maxVersion": "1.3"
    }

# اسکیما برای تنظیمات HTTP
class HTTPSettings(BaseModel):
    enable_http: bool = True
    http_settings: Dict = {
        "timeout": 300,
        "allowTransparent": False
    }
