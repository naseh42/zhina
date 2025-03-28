from pydantic import BaseModel, Field, validator
from typing import Optional
from datetime import datetime
from sqlalchemy.orm import Session
from backend.models import Subscription
from backend.database import get_db
from backend.config import settings
import logging
from uuid import UUID

logger = logging.getLogger(__name__)

class SubscriptionBase(BaseModel):
    """مدل پایه برای سابسکریپشن"""
    uuid: str = Field(
        ...,
        min_length=36,
        max_length=36,
        description="شناسه یکتا سابسکریپشن"
    )
    user_id: int = Field(
        ...,
        description="آیدی کاربر مالک سابسکریپشن"
    )

class SubscriptionCreate(SubscriptionBase):
    """مدل ایجاد سابسکریپشن جدید"""
    data_limit: int = Field(
        ...,
        gt=0,
        description="محدودیت ترافیک به بایت"
    )
    expiry_date: str = Field(
        ...,
        description="تاریخ انقضا به فرمت YYYY-MM-DD"
    )
    max_connections: int = Field(
        default=3,
        ge=1,
        description="حداکثر اتصالات همزمان"
    )
    is_active: bool = Field(
        default=True,
        description="وضعیت فعال/غیرفعال"
    )

    @validator('uuid')
    def validate_uuid(cls, v):
        try:
            UUID(v)
        except ValueError:
            raise ValueError("فرمت UUID نامعتبر است")
        return v

    @validator('expiry_date')
    def validate_expiry_date(cls, v):
        try:
            datetime.strptime(v, "%Y-%m-%d")
        except ValueError:
            raise ValueError("فرمت تاریخ باید YYYY-MM-DD باشد")
        return v

class SubscriptionUpdate(BaseModel):
    """مدل به‌روزرسانی سابسکریپشن"""
    data_limit: Optional[int] = Field(
        None,
        gt=0,
        description="محدودیت ترافیک به بایت"
    )
    expiry_date: Optional[str] = Field(
        None,
        description="تاریخ انقضا به فرمت YYYY-MM-DD"
    )
    max_connections: Optional[int] = Field(
        None,
        ge=1,
        description="حداکثر اتصالات همزمان"
    )
    is_active: Optional[bool] = Field(
        None,
        description="وضعیت فعال/غیرفعال"
    )

    @validator('expiry_date')
    def validate_expiry_date(cls, v):
        if v is not None:
            try:
                datetime.strptime(v, "%Y-%m-%d")
            except ValueError:
                raise ValueError("فرمت تاریخ باید YYYY-MM-DD باشد")
        return v

def create_subscription(db: Session, subscription: SubscriptionCreate) -> Subscription:
    """ایجاد سابسکریپشن جدید در دیتابیس"""
    try:
        db_subscription = Subscription(
            uuid=subscription.uuid,
            user_id=subscription.user_id,
            data_limit=subscription.data_limit,
            expiry_date=subscription.expiry_date,
            max_connections=subscription.max_connections,
            is_active=subscription.is_active,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow()
        )
        db.add(db_subscription)
        db.commit()
        db.refresh(db_subscription)
        logger.info(f"سابسکریپشن جدید ایجاد شد: {db_subscription.id}")
        return db_subscription
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در ایجاد سابسکریپشن: {str(e)}")
        raise

def get_subscription(db: Session, subscription_id: int) -> Optional[Subscription]:
    """دریافت سابسکریپشن بر اساس آیدی"""
    return db.query(Subscription).filter(Subscription.id == subscription_id).first()

def update_subscription(
    db: Session,
    subscription_id: int,
    subscription: SubscriptionUpdate
) -> Optional[Subscription]:
    """به‌روزرسانی سابسکریپشن موجود"""
    try:
        db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
        if not db_subscription:
            return None

        update_data = subscription.dict(exclude_unset=True)
        for field, value in update_data.items():
            setattr(db_subscription, field, value)
        
        db_subscription.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(db_subscription)
        logger.info(f"سابسکریپشن به‌روزرسانی شد: {subscription_id}")
        return db_subscription
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در به‌روزرسانی سابسکریپشن: {str(e)}")
        raise

def delete_subscription(db: Session, subscription_id: int) -> bool:
    """حذف سابسکریپشن از دیتابیس"""
    try:
        db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
        if not db_subscription:
            return False

        db.delete(db_subscription)
        db.commit()
        logger.info(f"سابسکریپشن حذف شد: {subscription_id}")
        return True
    except Exception as e:
        db.rollback()
        logger.error(f"خطا در حذف سابسکریپشن: {str(e)}")
        raise
