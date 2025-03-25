from pydantic import BaseModel, validator, field_validator
from typing import Dict, List, Optional
from datetime import datetime
from backend.database import get_db
from backend.models import Subscription
from sqlalchemy.orm import Session

class SubscriptionCreate(BaseModel):
    """
    مدل ایجاد سابسکریپشن جدید
    شامل اعتبارسنجی‌های لازم برای فیلدها
    """
    uuid: str
    data_limit: int
    expiry_date: str
    max_connections: int

    @validator("data_limit")
    def validate_data_limit(cls, value):
        """اعتبارسنجی محدودیت داده"""
        if value < 0:
            raise ValueError("محدودیت داده باید بزرگ‌تر از صفر باشد.")
        return value

    @validator("max_connections")
    def validate_max_connections(cls, value):
        """اعتبارسنجی حداکثر اتصالات"""
        if value < 1:
            raise ValueError("حداکثر اتصالات باید حداقل ۱ باشد.")
        return value

    @validator("expiry_date")
    def validate_expiry_date(cls, value):
        """اعتبارسنجی تاریخ انقضا"""
        try:
            datetime.strptime(value, "%Y-%m-%d")
        except ValueError:
            raise ValueError("فرمت تاریخ باید YYYY-MM-DD باشد")
        return value

class SubscriptionUpdate(BaseModel):
    """
    مدل به‌روزرسانی سابسکریپشن
    تمام فیلدها اختیاری هستند
    """
    data_limit: Optional[int] = Field(
        default=None,
        gt=0,
        description="محدودیت ترافیک به بایت (باید بزرگتر از صفر باشد)"
    )
    expiry_date: Optional[str] = Field(
        default=None,
        description="تاریخ انقضا به فرمت YYYY-MM-DD"
    )
    max_connections: Optional[int] = Field(
        default=None,
        gt=0,
        description="حداکثر اتصالات همزمان (باید بزرگتر از صفر باشد)"
    )

    @field_validator("expiry_date")
    @classmethod
    def validate_expiry_date(cls, value):
        """اعتبارسنجی تاریخ انقضا برای به‌روزرسانی"""
        if value is not None:
            try:
                datetime.strptime(value, "%Y-%m-%d")
            except ValueError:
                raise ValueError("فرمت تاریخ باید YYYY-MM-DD باشد")
        return value

def create_subscription(db: Session, subscription: SubscriptionCreate) -> Subscription:
    """
    ایجاد سابسکریپشن جدید در دیتابیس
    
    Args:
        db: جلسه دیتابیس
        subscription: مدل ایجاد سابسکریپشن
    
    Returns:
        شیء Subscription ایجاد شده
    """
    db_subscription = Subscription(
        uuid=subscription.uuid,
        data_limit=subscription.data_limit,
        expiry_date=subscription.expiry_date,
        max_connections=subscription.max_connections
    )
    db.add(db_subscription)
    db.commit()
    db.refresh(db_subscription)
    return db_subscription

def update_subscription(
    db: Session, 
    subscription_id: int, 
    subscription: SubscriptionUpdate
) -> Optional[Subscription]:
    """
    به‌روزرسانی سابسکریپشن موجود
    
    Args:
        db: جلسه دیتابیس
        subscription_id: ID سابسکریپشن
        subscription: مدل به‌روزرسانی
    
    Returns:
        شیء Subscription به‌روز شده یا None اگر پیدا نشد
    """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        return None

    if subscription.data_limit is not None:
        db_subscription.data_limit = subscription.data_limit
    if subscription.expiry_date is not None:
        db_subscription.expiry_date = subscription.expiry_date
    if subscription.max_connections is not None:
        db_subscription.max_connections = subscription.max_connections

    db.commit()
    db.refresh(db_subscription)
    return db_subscription

def delete_subscription(db: Session, subscription_id: int) -> bool:
    """
    حذف سابسکریپشن از دیتابیس
    
    Args:
        db: جلسه دیتابیس
        subscription_id: ID سابسکریپشن
    
    Returns:
        True اگر حذف موفق بود، False اگر سابسکریپشن پیدا نشد
    """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        return False

    db.delete(db_subscription)
    db.commit()
    return True
