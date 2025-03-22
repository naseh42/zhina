from pydantic import BaseModel, validator
from typing import Optional
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session
from backend.utils import generate_uuid

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

def create_user(db: Session, user: UserCreate):
    """ ایجاد کاربر جدید """
    user_uuid = generate_uuid()  # تولید UUID برای کاربر
    db_user = User(
        name=user.name,
        uuid=user_uuid,
        traffic_limit=user.traffic_limit,
        usage_duration=user.usage_duration,
        simultaneous_connections=user.simultaneous_connections,
        is_active=True
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user
