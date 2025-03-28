from pydantic import BaseModel, Field, validator
from typing import List, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from backend.models import User
from backend.database import get_db
from backend.utils import get_password_hash
from backend.config import settings
import logging

logger = logging.getLogger(__name__)

class AdminCreate(BaseModel):
    """مدل ایجاد ادمین جدید"""
    username: str = Field(..., min_length=3, max_length=50, example="admin123")
    password: str = Field(..., min_length=8, example="Strong@Pass123")
    permissions: List[str] = Field(
        default=["users.read", "users.write"],
        example=["users.read", "settings.write"],
        description="لیست دسترسی‌های ادمین"
    )

    @validator('username')
    def validate_username(cls, v):
        if not v.isalnum():
            raise ValueError("نام کاربری باید فقط شامل حروف و اعداد باشد")
        return v

class AdminUpdate(BaseModel):
    """مدل به‌روزرسانی ادمین"""
    username: Optional[str] = Field(None, min_length=3, max_length=50)
    password: Optional[str] = Field(None, min_length=8)
    permissions: Optional[List[str]] = None
    is_active: Optional[bool] = None

def create_admin(db: Session, admin_data: AdminCreate) -> User:
    """ایجاد ادمین جدید با دسترسی‌های تعریف شده"""
    try:
        # بررسی تکراری نبودن نام کاربری
        if db.query(User).filter(User.username == admin_data.username).first():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="نام کاربری قبلاً استفاده شده است"
            )

        db_admin = User(
            username=admin_data.username,
            hashed_password=get_password_hash(admin_data.password),
            is_admin=True,
            permissions=admin_data.permissions,
            created_at=datetime.utcnow(),
            last_login=datetime.utcnow()
        )
        
        db.add(db_admin)
        db.commit()
        logger.info(f"ادمین جدید ایجاد شد: {admin_data.username}")
        return db_admin
        
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در ایجاد ادمین: {str(e)}")
        raise

def update_admin(db: Session, admin_id: int, admin_data: AdminUpdate) -> Optional[User]:
    """به‌روزرسانی اطلاعات ادمین"""
    try:
        db_admin = db.query(User).filter(
            User.id == admin_id,
            User.is_admin == True
        ).first()
        
        if not db_admin:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="ادمین مورد نظر یافت نشد"
            )

        update_data = admin_data.dict(exclude_unset=True)
        
        if 'password' in update_data:
            update_data['hashed_password'] = get_password_hash(update_data.pop('password'))
            
        for field, value in update_data.items():
            setattr(db_admin, field, value)
            
        db_admin.updated_at = datetime.utcnow()
        db.commit()
        logger.info(f"اطلاعات ادمین به‌روزرسانی شد: {admin_id}")
        return db_admin
        
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در به‌روزرسانی ادمین: {str(e)}")
        raise

def delete_admin(db: Session, admin_id: int) -> bool:
    """حذف ادمین از سیستم"""
    try:
        db_admin = db.query(User).filter(
            User.id == admin_id,
            User.is_admin == True
        ).first()
        
        if not db_admin:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="ادمین مورد نظر یافت نشد"
            )

        db.delete(db_admin)
        db.commit()
        logger.info(f"ادمین حذف شد: {admin_id}")
        return True
        
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در حذف ادمین: {str(e)}")
        raise
