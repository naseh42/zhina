from pydantic import BaseModel, Field
from typing import Optional, List, Dict
from datetime import datetime

# اسکیمای کاربران
class UserBase(BaseModel):
    username: str = Field(
        ..., 
        min_length=3, 
        max_length=50, 
        pattern="^[a-zA-Z0-9_.-]+$",  # تغییر regex به pattern
        description="Username must be alphanumeric and between 3 and 50 characters."
    )
    uuid: str = Field(..., pattern="^[a-f0-9-]{36}$", description="UUID must be in a valid format.")
    traffic_limit: int = Field(..., ge=0, description="Traffic limit in MB.")
    usage_duration: int = Field(..., ge=0, description="Usage duration in minutes.")
    simultaneous_connections: int = Field(..., ge=1, le=10, description="Simultaneous connections allowed.")

class UserCreate(UserBase):
    pass

class UserUpdate(BaseModel):
    username: Optional[str] = Field(None, max_length=50)
    traffic_limit: Optional[int] = Field(None, ge=0)
    usage_duration: Optional[int] = Field(None, ge=0)
    simultaneous_connections: Optional[int] = Field(None, ge=1, le=10)

class UserResponse(UserBase):
    id: int
    is_active: bool
    created_at: Optional[datetime]
    updated_at: Optional[datetime]

    class Config:
        orm_mode = True

# اسکیمای دامنه‌ها
class DomainBase(BaseModel):
    name: str = Field(..., max_length=255, description="Domain name.")
    description: Optional[dict] = Field(None, description="Additional domain details.")

class DomainCreate(DomainBase):
    pass

class DomainUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=255)
    description: Optional[dict] = Field(None)

class DomainResponse(DomainBase):
    id: int
    owner_id: int
    created_at: Optional[datetime]
    updated_at: Optional[datetime]

    class Config:
        orm_mode = True

# اسکیمای تنظیمات
class SettingBase(BaseModel):
    language: str = Field(..., max_length=10, description="Language setting.")
    theme: str = Field(..., max_length=20, description="Theme setting.")
    enable_notifications: bool = Field(..., description="Enable or disable notifications.")
    preferences: Optional[dict] = Field(None, description="Additional preferences.")

class SettingCreate(SettingBase):
    pass

class SettingUpdate(BaseModel):
    language: Optional[str] = Field(None, max_length=10)
    theme: Optional[str] = Field(None, max_length=20)
    enable_notifications: Optional[bool] = Field(None)
    preferences: Optional[dict] = Field(None)

class SettingResponse(SettingBase):
    id: int
    created_at: Optional[datetime]
    updated_at: Optional[datetime]

    class Config:
        orm_mode = True

# اسکیمای اشتراک‌ها
class SubscriptionBase(BaseModel):
    uuid: str = Field(..., pattern="^[a-f0-9-]{36}$", description="UUID must be in a valid format.")
    data_limit: int = Field(..., ge=0, description="Data limit in GB.")
    expiry_date: datetime = Field(..., description="Expiry date in ISO format.")
    max_connections: int = Field(..., ge=1, description="Maximum allowed connections.")

class SubscriptionCreate(SubscriptionBase):
    pass

class SubscriptionUpdate(BaseModel):
    data_limit: Optional[int] = Field(None, ge=0)
    expiry_date: Optional[datetime] = Field(None)
    max_connections: Optional[int] = Field(None, ge=1)

class SubscriptionResponse(SubscriptionBase):
    id: int
    user_id: int
    created_at: Optional[datetime]
    updated_at: Optional[datetime]

    class Config:
        orm_mode = True

# اسکیمای تنظیمات اینباند Xray
class InboundConfig(BaseModel):
    port: int = Field(..., ge=1, le=65535, description="Port number.")
    protocol: str = Field(..., description="Protocol (e.g., vmess, vless).")
    settings: Optional[Dict] = Field(None, description="Dynamic settings.")
    stream_settings: Optional[Dict] = Field(None, description="Stream settings.")
    tag: Optional[str] = Field(None, description="Tag for the inbound.")

class InboundCreate(InboundConfig):
    pass

class InboundUpdate(BaseModel):
    port: Optional[int] = Field(None, ge=1, le=65535)
    protocol: Optional[str] = Field(None)
    settings: Optional[Dict] = Field(None)
    stream_settings: Optional[Dict] = Field(None)
    tag: Optional[str] = Field(None)

class InboundResponse(InboundConfig):
    id: int
    created_at: Optional[datetime]
    updated_at: Optional[datetime]

    class Config:
        orm_mode = True

# اسکیمای تنظیمات پنل منیجر
class PanelConfig(BaseModel):
    domain: Optional[str] = Field(None, description="Domain for the panel.")
    ssl_enabled: bool = Field(True, description="Enable SSL.")
    admin_link: Optional[str] = Field(None, description="Admin panel link.")

class PanelConfigResponse(PanelConfig):
    ssl_certificate: Optional[str] = Field(None, description="SSL certificate path.")
    created_at: Optional[datetime]
    updated_at: Optional[datetime]

    class Config:
        orm_mode = True
