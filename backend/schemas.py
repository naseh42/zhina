from pydantic import BaseModel, EmailStr, validator
from typing import Optional, List, Dict
from datetime import datetime

# مدل‌های احراز هویت جدید
class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    username: Optional[str] = None

class UserBase(BaseModel):
    username: str
    email: Optional[EmailStr] = None
    is_active: Optional[bool] = True

class UserCreate(UserBase):
    password: str

    @validator("password")
    def validate_password(cls, v):
        if len(v) < 8:
            raise ValueError("رمز عبور باید حداقل ۸ کاراکتر باشد")
        return v

class UserInDB(UserBase):
    hashed_password: str

# بقیه مدل‌های موجود (بدون تغییر)
class UserCreate(BaseModel):
    name: str
    traffic_limit: int = 0
    usage_duration: int = 0
    simultaneous_connections: int = 1

    # اعتبارسنجی‌های موجود...
    
class DomainCreate(BaseModel):
    # ... (بدون تغییر)

class SubscriptionCreate(BaseModel):
    # ... (بدون تغییر)

class NodeCreate(BaseModel):
    # ... (بدون تغییر)

class XraySettings(BaseModel):
    # ... (بدون تغییر)

class HTTPSettings(BaseModel):
    # ... (بدون تغییر)
