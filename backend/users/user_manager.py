from pydantic import BaseModel, validator
from typing import Optional, Dict, List
from datetime import datetime
from sqlalchemy.orm import Session
from backend.models import User, Inbound
from backend.utils import (
    generate_uuid,
    generate_subscription_link,
    generate_qr_code,
    calculate_traffic_usage,
    calculate_remaining_days
)

class UserCreate(BaseModel):
    name: str
    traffic_limit: int = 0
    usage_duration: int = 0
    simultaneous_connections: int = 1

    @validator("name")
    def validate_name(cls, value):
        if len(value) < 3:
            raise ValueError("نام باید حداقل ۳ کاراکتر داشته باشد")
        return value

    @validator("*")
    def validate_positive_numbers(cls, value):
        if value < 0:
            raise ValueError("مقدار نمی‌تواند منفی باشد")
        return value

class UserUpdate(BaseModel):
    name: Optional[str] = None
    traffic_limit: Optional[int] = None
    usage_duration: Optional[int] = None
    simultaneous_connections: Optional[int] = None

class UserManager:
    def __init__(self, db: Session):
        self.db = db
    
    # --- عملیات پایه ---
    def create(self, user_data: UserCreate) -> User:
        """ایجاد کاربر جدید"""
        user = User(
            name=user_data.name,
            uuid=generate_uuid(),
            traffic_limit=user_data.traffic_limit,
            usage_duration=user_data.usage_duration,
            simultaneous_connections=user_data.simultaneous_connections
        )
        self.db.add(user)
        self.db.commit()
        return user

    def update(self, user_id: int, user_data: UserUpdate) -> Optional[User]:
        """به‌روزرسانی کاربر"""
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return None

        if user_data.name:
            user.name = user_data.name
        if user_data.traffic_limit:
            user.traffic_limit = user_data.traffic_limit
        # ... سایر فیلدها

        self.db.commit()
        return user

    def delete(self, user_id: int) -> bool:
        """حذف کاربر"""
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return False

        self.db.delete(user)
        self.db.commit()
        return True

    # --- عملیات پیشرفته ---
    def get_dashboard(self, user_id: int, domain: str) -> Dict:
        """دریافت اطلاعات کامل کاربر برای داشبورد"""
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            return None

        return {
            "user": self._basic_info(user),
            "subscription": self._subscription_info(user, domain),
            "stats": self._usage_stats(user)
        }

    def _basic_info(self, user: User) -> Dict:
        """اطلاعات پایه کاربر"""
        return {
            "name": user.name,
            "uuid": user.uuid,
            "is_active": user.is_active
        }

    def _subscription_info(self, user: User, domain: str) -> Dict:
        """اطلاعات سابسکریپشن"""
        link = generate_subscription_link(domain, user.uuid)
        return {
            "link": link,
            "qr_code": generate_qr_code(link),
            "configs": self._get_user_configs(user)
        }

    def _usage_stats(self, user: User) -> Dict:
        """آمار استفاده"""
        return {
            "traffic": f"{user.traffic_used}/{user.traffic_limit}",
            "usage_percentage": calculate_traffic_usage(user.traffic_limit, user.traffic_used),
            "remaining_days": calculate_remaining_days(user.expiry_date)
        }

    def _get_user_configs(self, user: User) -> List[Dict]:
        """دریافت کانفیگ‌های کاربر"""
        inbounds = self.db.query(Inbound).filter(Inbound.user_id == user.id).all()
        return [{
            "protocol": inbound.protocol,
            "port": inbound.port,
            "link": f"{inbound.protocol}://{user.uuid}@example.com:{inbound.port}"
        } for inbound in inbounds]
