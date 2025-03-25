from pydantic import BaseModel, validator, Field
from typing import Optional
from datetime import datetime
from backend.database import get_db
from backend.models import Subscription
from sqlalchemy.orm import Session

class SubscriptionCreate(BaseModel):
    """
    مدل ایجاد سابسکریپشن جدید
    """
    uuid: str
    data_limit: int
    expiry_date: str
    max_connections: int

    @validator("data_limit")
    def validate_data_limit(cls, v):
        if v < 0:
            raise ValueError("محدودیت داده باید بزرگ‌تر از صفر باشد")
        return v

    @validator("max_connections")
    def validate_max_connections(cls, v):
        if v < 1:
            raise ValueError("حداکثر اتصالات باید حداقل ۱ باشد")
        return v

    @validator("expiry_date")
    def validate_expiry_date(cls, v):
        try:
            datetime.strptime(v, "%Y-%m-%d")
        except ValueError:
            raise ValueError("فرمت تاریخ باید YYYY-MM-DD باشد")
        return v

class SubscriptionUpdate(BaseModel):
    """
    مدل به‌روزرسانی سابسکریپشن
    """
    data_limit: Optional[int] = Field(
        default=None,
        description="محدودیت داده به بایت"
    )
    expiry_date: Optional[str] = Field(
        default=None,
        description="تاریخ انقضا به فرمت YYYY-MM-DD"
    )
    max_connections: Optional[int] = Field(
        default=None,
        description="حداکثر اتصالات همزمان"
    )

    @validator("expiry_date")
    def validate_expiry_date(cls, v):
        if v is not None:
            try:
                datetime.strptime(v, "%Y-%m-%d")
            except ValueError:
                raise ValueError("فرمت تاریخ باید YYYY-MM-DD باشد")
        return v

def create_subscription(db: Session, subscription: SubscriptionCreate) -> Subscription:
    """
    ایجاد سابسکریپشن جدید در دیتابیس
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
    """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        return False

    db.delete(db_subscription)
    db.commit()
    return True
