from pydantic import BaseModel, Field, validator
from typing import Optional, Dict, List
from datetime import datetime
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from backend.models import User, Inbound, Subscription
from backend.utils import (
    generate_uuid,
    generate_subscription_link,
    generate_qr_code,
    calculate_traffic_usage,
    calculate_remaining_days,
    format_bytes,
    get_password_hash
)
from backend.config import settings
import logging
from pathlib import Path  # ADDED

logger = logging.getLogger(__name__)

class UserCreate(BaseModel):
    """مدل ایجاد کاربر جدید"""
    username: str = Field(..., min_length=3, max_length=50, example="user123")
    email: Optional[str] = Field(None, example="user@example.com")
    password: str = Field(..., min_length=8, example="StrongPass123!")
    traffic_limit: int = Field(default=settings.DEFAULT_TRAFFIC_LIMIT, ge=0)
    usage_duration: int = Field(default=settings.DEFAULT_USAGE_DURATION, ge=1)
    simultaneous_connections: int = Field(default=3, ge=1)

    @validator('username')
    def validate_username(cls, v):
        if not v.isalnum():
            raise ValueError("نام کاربری باید فقط شامل حروف و اعداد باشد")
        return v

class UserUpdate(BaseModel):
    """مدل به‌روزرسانی کاربر"""
    username: Optional[str] = Field(None, min_length=3, max_length=50)
    email: Optional[str] = None
    password: Optional[str] = Field(None, min_length=8)
    traffic_limit: Optional[int] = Field(None, ge=0)
    usage_duration: Optional[int] = Field(None, ge=1)
    simultaneous_connections: Optional[int] = Field(None, ge=1)
    is_active: Optional[bool] = None

class UserManager:
    """مدیریت جامع کاربران سیستم"""
    
    def __init__(self, db: Session):
        self.db = db
        self.user_data_dir = Path("/opt/zhina/user_data")  # ADDED
    
    def create(self, user_data: UserCreate) -> User:
        """ایجاد کاربر جدید با تمام وابستگی‌ها"""
        try:
            # بررسی تکراری نبودن نام کاربری
            if self.db.query(User).filter(User.username == user_data.username).first():
                raise ValueError("نام کاربری قبلاً استفاده شده است")

            # ایجاد دایرکتوری کاربر
            user_dir = self.user_data_dir / user_data.username
            user_dir.mkdir(parents=True, exist_ok=True)  # ADDED

            # ایجاد کاربر
            user = User(
                username=user_data.username,
                email=user_data.email,
                hashed_password=get_password_hash(user_data.password),
                uuid=generate_uuid(),
                traffic_limit=user_data.traffic_limit,
                usage_duration=user_data.usage_duration,
                simultaneous_connections=user_data.simultaneous_connections,
                created_at=datetime.utcnow(),
                last_activity=datetime.utcnow(),
                data_dir=str(user_dir)  # ADDED
            )
            
            self.db.add(user)
            self.db.commit()
            logger.info(f"کاربر جدید ایجاد شد: {user.username}")
            return user
            
        except Exception as e:
            self.db.rollback()
            logger.error(f"خطا در ایجاد کاربر: {str(e)}")
            raise

    def update(self, user_id: int, user_data: UserUpdate) -> Optional[User]:
        """به‌روزرسانی اطلاعات کاربر"""
        try:
            user = self.db.query(User).filter(User.id == user_id).first()
            if not user:
                return None

            update_data = user_data.dict(exclude_unset=True)
            
            if 'password' in update_data:
                update_data['hashed_password'] = get_password_hash(update_data.pop('password'))
                
            for field, value in update_data.items():
                setattr(user, field, value)
                
            user.updated_at = datetime.utcnow()
            self.db.commit()
            logger.info(f"کاربر به‌روزرسانی شد: {user_id}")
            return user
            
        except Exception as e:
            self.db.rollback()
            logger.error(f"خطا در به‌روزرسانی کاربر {user_id}: {str(e)}")
            raise

    def delete(self, user_id: int) -> bool:
        """حذف کامل کاربر و وابستگی‌ها"""
        try:
            user = self.db.query(User).filter(User.id == user_id).first()
            if not user:
                return False

            # حذف دایرکتوری کاربر
            user_dir = Path(user.data_dir)  # ADDED
            if user_dir.exists():  # ADDED
                import shutil
                shutil.rmtree(user_dir)  # ADDED

            # حذف وابستگی‌ها
            self.db.query(Subscription).filter(Subscription.user_id == user_id).delete()
            self.db.query(Inbound).filter(Inbound.user_id == user_id).delete()
            
            # حذف کاربر
            self.db.delete(user)
            self.db.commit()
            logger.info(f"کاربر حذف شد: {user_id}")
            return True
            
        except Exception as e:
            self.db.rollback()
            logger.error(f"خطا در حذف کاربر {user_id}: {str(e)}")
            raise

    # ... (بقیه توابع بدون تغییر)

# ============ توابع اضافه شده ============
def get_user_by_uuid(db: Session, uuid: str) -> Optional[User]:  # ADDED
    """دریافت کاربر بر اساس UUID"""
    return db.query(User).filter(User.uuid == uuid).first()

def count_active_users(db: Session) -> int:  # ADDED
    """شمارش کاربران فعال"""
    return db.query(User).filter(User.is_active == True).count()
