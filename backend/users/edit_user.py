from pydantic import BaseModel, validator
from typing import Optional
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session

class UserUpdate(BaseModel):
    name: Optional[str] = None
    traffic_limit: Optional[int] = None
    usage_duration: Optional[int] = None
    simultaneous_connections: Optional[int] = None

    @validator("name")
    def validate_name(cls, value):
        if value and len(value) < 3:
            raise ValueError("نام باید حداقل ۳ کاراکتر داشته باشد.")
        return value

    @validator("traffic_limit")
    def validate_traffic_limit(cls, value):
        if value and value < 0:
            raise ValueError("محدودیت ترافیک باید بزرگ‌تر یا مساوی صفر باشد.")
        return value

    @validator("usage_duration")
    def validate_usage_duration(cls, value):
        if value and value < 0:
            raise ValueError("مدت زمان استفاده باید بزرگ‌تر یا مساوی صفر باشد.")
        return value

    @validator("simultaneous_connections")
    def validate_simultaneous_connections(cls, value):
        if value and value < 1:
            raise ValueError("حداقل تعداد اتصالات هم‌زمان باید ۱ باشد.")
        return value

def update_user(db: Session, user_id: int, user: UserUpdate):
    """ به‌روزرسانی اطلاعات کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return None

    if user.name:
        db_user.name = user.name
    if user.traffic_limit:
        db_user.traffic_limit = user.traffic_limit
    if user.usage_duration:
        db_user.usage_duration = user.usage_duration
    if user.simultaneous_connections:
        db_user.simultaneous_connections = user.simultaneous_connections

    db.commit()
    db.refresh(db_user)
    return db_user
