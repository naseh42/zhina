from pydantic import BaseModel, Field, EmailStr, validator
from typing import Optional, Dict, List, Literal
from datetime import datetime, timedelta
from enum import Enum

class Token(BaseModel):
    access_token: str = Field(..., example="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...")
    token_type: str = Field(default="bearer")

class TokenData(BaseModel):
    username: Optional[str] = Field(None, example="admin")

class UserBase(BaseModel):
    username: str = Field(..., min_length=3, max_length=50, example="user123")
    email: Optional[EmailStr] = Field(None, example="user@example.com")
    is_active: Optional[bool] = Field(default=True)

class UserCreate(UserBase):
    password: str = Field(..., min_length=8, example="Str0ngP@ss")
    traffic_limit: int = Field(default=0, ge=0, description="Bytes")
    usage_duration: int = Field(default=30, ge=1, description="Days")
    simultaneous_connections: int = Field(default=3, ge=1)

class UserInDB(UserBase):
    id: int
    uuid: str
    created_at: datetime
    updated_at: Optional[datetime]

    class Config:
        from_attributes = True

class DomainProtocol(str, Enum):
    VMESS = "vmess"
    VLESS = "vless"
    TROJAN = "trojan"

class DomainCreate(BaseModel):
    name: str = Field(..., min_length=3, max_length=253, example="example.com")
    protocol: DomainProtocol = Field(default=DomainProtocol.VMESS)
    cdn_enabled: bool = Field(default=False)

class SubscriptionCreate(BaseModel):
    user_id: int
    data_limit: int = Field(default=10737418240, ge=0)
    expiry_date: datetime = Field(default_factory=lambda: datetime.now() + timedelta(days=30))
    max_connections: int = Field(default=3, ge=1)

class NodeProtocol(str, Enum):
    VMESS = "vmess"
    VLESS = "vless"
    TROJAN = "trojan"
    SHADOWSOCKS = "shadowsocks"

class NodeCreate(BaseModel):
    name: str = Field(..., min_length=3, max_length=100)
    ip_address: str = Field(..., example="192.168.1.1")
    port: int = Field(..., ge=1, le=65535, example=443)
    protocol: NodeProtocol

class XraySettings(BaseModel):
    enable_tls: bool = Field(default=True)
    tls_cert_path: Optional[str] = Field(None, example="/etc/ssl/cert.pem")
    tls_key_path: Optional[str] = Field(None, example="/etc/ssl/key.pem")

class ServerNetworkSettings(BaseModel):
    ip: str = Field(..., example="192.168.1.1")
    port: int = Field(default=8001, ge=1024, le=65535)
    host: str = Field(default="0.0.0.0")

class ServerHealthCheck(BaseModel):
    status: Literal["online", "offline", "degraded"]
    services: Dict[str, str] = Field(default={"database": "unknown", "xray": "unknown"})

class ServerStats(BaseModel):
    cpu_usage: float = Field(..., ge=0, le=100)
    memory_usage: float = Field(..., ge=0, le=100)
    active_connections: int = Field(..., ge=0)
