from pydantic import BaseModel, Field, validator
from typing import Optional
from datetime import datetime
from sqlalchemy.orm import Session
from backend.models import User
from backend.database import get_db
from backend.utils import get_password_hash
from backend.config import settings
import logging
from .xray_manager import xray_manager

logger = logging.getLogger(__name__)

class UserUpdate(BaseModel):
    """
    مدل به‌روزرسانی اطلاعات کاربر
    
    تمام فیلدها اختیاری هستند و فقط فیلدهای ارسال شده به‌روزرسانی می‌شوند
    """
    username: Optional[str] = Field(
        None,
        min_length=3,
        max_length=50,
        example="new_username",
        description="نام کاربری جدید"
    )
    email: Optional[str] = Field(
        None,
        example="new_email@example.com",
        description="ایمیل جدید"
    )
    password: Optional[str] = Field(
        None,
        min_length=8,
        example="NewP@ssw0rd",
        description="رمز عبور جدید (حداقل ۸ کاراکتر)"
    )
    traffic_limit: Optional[int] = Field(
        None,
        ge=0,
        example=10737418240,
        description="محدودیت ترافیک جدید به بایت"
    )
    usage_duration: Optional[int] = Field(
        None,
        ge=0,
        example=30,
        description="مدت زمان اعتبار به روز"
    )
    simultaneous_connections: Optional[int] = Field(
        None,
        ge=1,
        example=3,
        description="حداکثر اتصالات همزمان"
    )
    is_active: Optional[bool] = Field(
        None,
        example=True,
        description="وضعیت فعال/غیرفعال کردن کاربر"
    )

    @validator('username')
    def validate_username(cls, v):
        if v and not v.isalnum():
            raise ValueError("نام کاربری باید فقط شامل حروف و اعداد باشد")
        return v

    @validator('email')
    def validate_email(cls, v):
        if v and '@' not in v:
            raise ValueError("فرمت ایمیل نامعتبر است")
        return v

def update_user(db: Session, user_id: int, user_data: UserUpdate) -> Optional[User]:
    """
    به‌روزرسانی اطلاعات کاربر در سیستم
    
    Args:
        db: Session دیتابیس
        user_id: آیدی کاربر مورد نظر
        user_data: داده‌های جدید برای به‌روزرسانی
        
    Returns:
        User: اطلاعات کاربر به‌روزرسانی شده
        None: اگر کاربر یافت نشد
    """
    try:
        # 1. یافتن کاربر
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            logger.warning(f"کاربر با آیدی {user_id} یافت نشد")
            return None

        # 2. به‌روزرسانی فیلدها
        update_fields = user_data.dict(exclude_unset=True)
        
        if 'password' in update_fields:
            update_fields['hashed_password'] = get_password_hash(update_fields.pop('password'))
            
        for field, value in update_fields.items():
            setattr(db_user, field, value)
            
        db_user.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(db_user)

        # 3. اعمال تغییرات در Xray در صورت نیاز
        if settings.XRAY_AUTO_UPDATE and ('traffic_limit' in update_fields or 'is_active' in update_fields):
            xray_manager.apply_config()

        logger.info(f"اطلاعات کاربر {user_id} با موفقیت به‌روزرسانی شد")
        return db_user

    except Exception as e:
        db.rollback()
        logger.error(f"خطا در به‌روزرسانی کاربر {user_id}: {str(e)}")
        raise
