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
    
    def create(self, user_data: UserCreate) -> User:
        """ایجاد کاربر جدید با تمام وابستگی‌ها"""
        try:
            # بررسی تکراری نبودن نام کاربری
            if self.db.query(User).filter(User.username == user_data.username).first():
                raise ValueError("نام کاربری قبلاً استفاده شده است")

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
                last_activity=datetime.utcnow()
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

    def get_dashboard(self, user_id: int) -> Dict:
        """دریافت اطلاعات کامل داشبورد کاربر"""
        try:
            user = self.db.query(User).filter(User.id == user_id).first()
            if not user:
                raise HTTPException(status_code=404, detail="کاربر یافت نشد")

            subscription = self.db.query(Subscription)\
                                .filter(Subscription.user_id == user_id)\
                                .order_by(Subscription.created_at.desc())\
                                .first()

            return {
                "user": self._get_basic_info(user),
                "subscription": self._get_subscription_info(user, subscription),
                "usage": self._get_usage_stats(user, subscription)
            }
            
        except Exception as e:
            logger.error(f"خطا در دریافت داشبورد کاربر {user_id}: {str(e)}")
            raise

    def _get_basic_info(self, user: User) -> Dict:
        return {
            "username": user.username,
            "email": user.email,
            "uuid": user.uuid,
            "created_at": user.created_at,
            "last_activity": user.last_activity
        }

    def _get_subscription_info(self, user: User, subscription: Subscription) -> Dict:
        sub_link = generate_subscription_link(settings.DOMAIN, user.uuid)
        return {
            "link": sub_link,
            "qr_code": generate_qr_code(sub_link),
            "configs": self._get_user_configs(user),
            "status": "active" if subscription and subscription.is_active else "inactive"
        }

    def _get_usage_stats(self, user: User, subscription: Subscription) -> Dict:
        return {
            "traffic": {
                "used": format_bytes(user.traffic_used),
                "limit": format_bytes(user.traffic_limit),
                "percentage": calculate_traffic_usage(user.traffic_limit, user.traffic_used)
            },
            "remaining_days": calculate_remaining_days(subscription.expiry_date) if subscription else 0
        }

    def _get_user_configs(self, user: User) -> List[Dict]:
        inbounds = self.db.query(Inbound).filter(Inbound.user_id == user.id).all()
        return [{
            "protocol": inbound.protocol,
            "port": inbound.port,
            "link": f"{settings.PANEL_URL}/config/{inbound.protocol}/{user.uuid}"
        } for inbound in inbounds]
