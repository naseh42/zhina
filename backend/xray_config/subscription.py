from pydantic import BaseModel
from typing import Dict, List, Optional
from backend.database import get_db
from backend.models import Subscription
from sqlalchemy.orm import Session

class SubscriptionCreate(BaseModel):
    uuid: str
    data_limit: int
    expiry_date: str
    max_connections: int

    @validator("data_limit")
    def validate_data_limit(cls, value):
        if value < 0:
            raise ValueError("محدودیت داده باید بزرگ‌تر از صفر باشد.")
        return value

    @validator("max_connections")
    def validate_max_connections(cls, value):
        if value < 1:
            raise ValueError("حداکثر اتصالات باید حداقل ۱ باشد.")
        return value

class SubscriptionUpdate(BaseModel):
    data_limit: Optional[int] = None
    expiry_date: Optional[str] = None
    max_connections: Optional[int] = None

def create_subscription(db: Session, subscription: SubscriptionCreate):
    """ ایجاد سابسکریپشن جدید """
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

def update_subscription(db: Session, subscription_id: int, subscription: SubscriptionUpdate):
    """ به‌روزرسانی سابسکریپشن """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        return None

    if subscription.data_limit:
        db_subscription.data_limit = subscription.data_limit
    if subscription.expiry_date:
        db_subscription.expiry_date = subscription.expiry_date
    if subscription.max_connections:
        db_subscription.max_connections = subscription.max_connections

    db.commit()
    db.refresh(db_subscription)
    return db_subscription

def delete_subscription(db: Session, subscription_id: int):
    """ حذف سابسکریپشن """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        return False

    db.delete(db_subscription)
    db.commit()
    return True
