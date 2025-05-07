from pydantic import BaseModel, Field, ConfigDict, field_validator
from datetime import datetime, timedelta
from typing import Optional, Dict, List, Literal, Union
from enum import Enum

# -------------------- Authentication --------------------
class Token(BaseModel):
    access_token: str = Field(..., examples=["eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."])
    token_type: str = Field(default="bearer")

class TokenData(BaseModel):
    username: Optional[str] = Field(None, examples=["admin"])

# -------------------- User Models --------------------
class UserBase(BaseModel):
    username: str = Field(..., min_length=3, max_length=50, examples=["user123"])
    email: Optional[str] = Field(None, examples=["user@example.com"])
    is_active: Optional[bool] = Field(default=True)

class UserCreate(UserBase):
    password: str = Field(..., min_length=8, examples=["Str0ngP@ss"])
    traffic_limit: int = Field(default=0, ge=0, description="محدودیت ترافیک به بایت")
    usage_duration: int = Field(default=30, ge=1, description="مدت زمان استفاده به روز")
    simultaneous_connections: int = Field(default=3, ge=1)

class UserResponse(UserBase):
    id: int
    uuid: str
    created_at: datetime
    updated_at: Optional[datetime]
    traffic_limit: int
    traffic_used: int
    usage_duration: int
    remaining_days: int
    simultaneous_connections: int
    expiry_date: Optional[datetime] = None
    
    model_config = ConfigDict(from_attributes=True)

class User(UserResponse):
    pass

class UserInDB(UserResponse):
    hashed_password: str

# -------------------- Domain Models --------------------
class DomainProtocol(str, Enum):
    VMESS = "vmess"
    VLESS = "vless"
    TROJAN = "trojan"

class DomainCreate(BaseModel):
    name: str = Field(..., min_length=3, max_length=253, examples=["example.com"])
    protocol: DomainProtocol = Field(default=DomainProtocol.VMESS)
    cdn_enabled: bool = Field(default=False)

class DomainResponse(BaseModel):
    id: int
    name: str
    protocol: DomainProtocol
    cdn_enabled: bool
    created_at: datetime
    updated_at: Optional[datetime]
    owner_id: int
    
    model_config = ConfigDict(from_attributes=True)

class Domain(DomainResponse):
    pass

# -------------------- Subscription Models --------------------
class SubscriptionCreate(BaseModel):
    user_id: int
    data_limit: int = Field(default=10737418240, ge=0)
    expiry_date: datetime = Field(default_factory=lambda: datetime.now() + timedelta(days=30))
    max_connections: int = Field(default=3, ge=1)

class SubscriptionLink(BaseModel):
    """مدل لینک سابسکریپشن"""
    link: str = Field(..., description="لینک کامل سابسکریپشن")
    domain_names: List[str] = Field(..., description="لیست نام دامنه‌های موجود در لینک")
    generated_at: datetime = Field(default_factory=datetime.now)
    expires_at: Optional[datetime] = Field(None, description="تاریخ انقضای لینک")
    
    model_config = ConfigDict(from_attributes=True)

# -------------------- Node Models --------------------
class NodeProtocol(str, Enum):
    VMESS = "vmess"
    VLESS = "vless"
    TROJAN = "trojan"
    SHADOWSOCKS = "shadowsocks"

class NodeCreate(BaseModel):
    name: str = Field(..., min_length=3, max_length=100)
    ip_address: str = Field(..., examples=["192.168.1.1"])
    port: int = Field(..., ge=1, le=65535, examples=[443])
    protocol: NodeProtocol

class NodeResponse(BaseModel):
    id: int
    name: str
    ip_address: str
    port: int
    protocol: NodeProtocol
    is_active: bool
    created_at: datetime
    
    model_config = ConfigDict(from_attributes=True)

# -------------------- Xray Settings --------------------
class XraySettings(BaseModel):
    enable_tls: bool = Field(default=True)
    tls_cert_path: Optional[str] = Field(None, examples=["/etc/ssl/cert.pem"])
    tls_key_path: Optional[str] = Field(None, examples=["/etc/ssl/key.pem"])

class XrayConfigResponse(BaseModel):
    config: Dict[str, Union[str, int, bool, List[Dict]]]
    status: str
    last_updated: datetime

# -------------------- Server Models --------------------
class ServerNetworkSettings(BaseModel):
    ip: str = Field(..., examples=["192.168.1.1"])
    port: int = Field(default=8001, ge=1024, le=65535)
    host: str = Field(default="0.0.0.0")

class ServerHealthCheck(BaseModel):
    status: Literal["online", "offline", "degraded"]
    services: Dict[str, str] = Field(default={"database": "unknown", "xray": "unknown"})

class ServerStats(BaseModel):
    cpu_usage: float = Field(..., ge=0, le=100)
    memory_usage: float = Field(..., ge=0, le=100)
    active_connections: int = Field(..., ge=0)
    total_users: int
    online_users: int

from pydantic import BaseModel, Field, field_validator
from typing import Optional, Dict
from datetime import datetime

class InboundCreate(BaseModel):
    port: int = Field(..., ge=1, le=65535, description="پورت اینباند (1-65535)")
    protocol: str = Field(..., description="پروتکل اینباند")
    settings: Dict = Field(default_factory=dict, description="تنظیمات اختصاصی پروتکل")
    stream_settings: Dict = Field(default_factory=dict, description="تنظیمات جریان داده")
    tag: Optional[str] = Field(None, max_length=50, description="برچسب اینباند")
    remark: Optional[str] = Field(None, max_length=100, description="توضیحات اختیاری")

    @field_validator('protocol')
    @classmethod
    def validate_protocol(cls, v):
        valid_protocols = ["vmess", "vless", "trojan", "shadowsocks", "http", "socks"]
        if v.lower() not in valid_protocols:
            raise ValueError(f"پروتکل نامعتبر. باید یکی از این موارد باشد: {', '.join(valid_protocols)}")
        return v.lower()

    @field_validator('settings')
    @classmethod
    def validate_settings(cls, v, values):
        protocol = values.data.get('protocol')
        if protocol == 'vmess' and 'clients' not in v:
            raise ValueError("تنظیمات vmess باید شامل لیست clients باشد")
        return v


class InboundUpdate(BaseModel):
    port: Optional[int] = Field(None, ge=1, le=65535)
    protocol: Optional[str] = None
    settings: Optional[Dict] = None
    stream_settings: Optional[Dict] = None
    tag: Optional[str] = Field(None, max_length=50)
    remark: Optional[str] = Field(None, max_length=100)

    @field_validator('protocol')
    @classmethod
    def validate_protocol(cls, v):
        if v is not None:
            valid_protocols = ["vmess", "vless", "trojan", "shadowsocks", "http", "socks"]
            if v.lower() not in valid_protocols:
                raise ValueError(f"پروتکل نامعتبر. باید یکی از این موارد باشد: {', '.join(valid_protocols)}")
            return v.lower()
        return v


class InboundResponse(BaseModel):
    id: int
    port: int
    protocol: str
    settings: Dict
    stream_settings: Dict
    tag: Optional[str]
    remark: Optional[str]
    created_at: datetime
    updated_at: datetime
    config_path: Optional[str]
    is_active: Optional[bool]

    class Config:
        orm_mode = True
