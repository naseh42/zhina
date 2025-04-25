from pydantic import BaseModel, Field, EmailStr, validator
from typing import Optional
from datetime import datetime
from sqlalchemy.orm import Session
from backend.models import User
from backend.database import get_db
from backend.utils import (
    get_password_hash,
    generate_uuid,
    generate_random_password
)
from backend.config import settings
import logging
import qrcode
from io import BytesIO
from fastapi.responses import StreamingResponse

logger = logging.getLogger(__name__)

class UserBase(BaseModel):
    """مدل پایه کاربر"""
    username: str = Field(
        ...,
        min_length=3,
        max_length=50,
        example="user123",
        description="نام کاربری منحصر به فرد"
    )
    email: Optional[EmailStr] = Field(
        None,
        example="user@example.com",
        description="آدرس ایمیل (اختیاری)"
    )

class UserCreate(UserBase):
    """مدل ایجاد کاربر جدید"""
    password: str = Field(
        ...,
        min_length=8,
        example="Str0ngP@ss123",
        description="رمز عبور با حداقل ۸ کاراکتر"
    )
    traffic_limit: int = Field(
        default=settings.DEFAULT_TRAFFIC_LIMIT,
        ge=0,
        description="محدودیت ترافیک به بایت"
    )
    usage_duration: int = Field(
        default=settings.DEFAULT_USAGE_DURATION,
        ge=0,
        description="مدت زمان اعتبار به روز"
    )
    simultaneous_connections: int = Field(
        default=settings.DEFAULT_MAX_CONNECTIONS,
        ge=1,
        description="حداکثر اتصالات همزمان"
    )

    @validator('username')
    def validate_username(cls, v):
        if not v.isalnum():
            raise ValueError("نام کاربری باید فقط شامل حروف و اعداد باشد")
        return v

class UserUpdate(BaseModel):
    """مدل به‌روزرسانی کاربر"""
    username: Optional[str] = Field(
        None,
        min_length=3,
        max_length=50
    )
    email: Optional[EmailStr] = None
    password: Optional[str] = Field(
        None,
        min_length=8
    )
    traffic_limit: Optional[int] = Field(
        None,
        ge=0
    )
    usage_duration: Optional[int] = Field(
        None,
        ge=0
    )
    simultaneous_connections: Optional[int] = Field(
        None,
        ge=1
    )
    is_active: Optional[bool] = None

class UserInDB(UserBase):
    """مدل نمایش کاربر از دیتابیس"""
    id: int
    uuid: str
    traffic_limit: int
    usage_duration: int
    simultaneous_connections: int
    is_active: bool
    created_at: datetime
    updated_at: Optional[datetime]

    class Config:
        from_attributes = True

def generate_qr_code(url: str) -> StreamingResponse:
    """ساخت QR کد برای لینک اشتراک"""
    img = qrcode.make(url)
    img_io = BytesIO()
    img.save(img_io, 'PNG')
    img_io.seek(0)
    return StreamingResponse(img_io, media_type="image/png")

def create_user(db: Session, user_data: UserCreate) -> User:
    """ایجاد کاربر جدید در سیستم"""
    try:
        # بررسی تکراری نبودن نام کاربری
        existing_user = db.query(User).filter(User.username == user_data.username).first()
        if existing_user:
            raise ValueError("نام کاربری قبلاً استفاده شده است")

        # ایجاد کاربر جدید
        db_user = User(
            username=user_data.username,
            email=user_data.email,
            hashed_password=get_password_hash(user_data.password),
            uuid=generate_uuid(),
            traffic_limit=user_data.traffic_limit,
            usage_duration=user_data.usage_duration,
            simultaneous_connections=user_data.simultaneous_connections,
            is_active=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow()
        )
        
        db.add(db_user)
        db.commit()
        db.refresh(db_user)

        # ساخت لینک اشتراک
        subscription_link = f"{settings.SUBSCRIPTION_URL}/{db_user.uuid}"
        
        # ساخت QR کد از لینک اشتراک
        qr_code = generate_qr_code(subscription_link)

        logger.info(f"کاربر جدید ایجاد شد: {db_user.username}, لینک اشتراک: {subscription_link}")
        return db_user, qr_code  # بازگشت کاربر و QR کد
        
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در ایجاد کاربر: {str(e)}")
        raise

def get_user(db: Session, user_id: int) -> Optional[User]:
    """دریافت کاربر بر اساس ID"""
    return db.query(User).filter(User.id == user_id).first()

def get_user_by_username(db: Session, username: str) -> Optional[User]:
    """دریافت کاربر بر اساس نام کاربری"""
    return db.query(User).filter(User.username == username).first()

def update_user(db: Session, user_id: int, user_data: UserUpdate) -> Optional[User]:
    """به‌روزرسانی اطلاعات کاربر"""
    try:
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            return None

        update_data = user_data.dict(exclude_unset=True)
        
        if 'password' in update_data:
            update_data['hashed_password'] = get_password_hash(update_data.pop('password'))
            
        for field, value in update_data.items():
            setattr(db_user, field, value)
            
        db_user.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(db_user)
        
        logger.info(f"اطلاعات کاربر به‌روزرسانی شد: {db_user.username}")
        return db_user
        
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در به‌روزرسانی کاربر: {str(e)}")
        raise

def delete_user(db: Session, user_id: int) -> bool:
    """حذف کاربر از سیستم"""
    try:
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            return False

        db.delete(db_user)
        db.commit()
        
        logger.info(f"کاربر حذف شد: ID {user_id}")
        return True
        
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در حذف کاربر: {str(e)}")
        raise
