from typing import Dict
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session
from backend.utils import generate_subscription_link

def get_user_subscription_link(db: Session, user_id: int, domain: str) -> str:
    """ دریافت لینک سابسکریپشن کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return None

    return generate_subscription_link(domain, db_user.uuid)

def get_user_subscription_info(db: Session, user_id: int) -> Dict:
    """ دریافت اطلاعات سابسکریپشن کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return None

    return {
        "name": db_user.name,
        "uuid": db_user.uuid,
        "traffic_limit": db_user.traffic_limit,
        "traffic_used": db_user.traffic_used,
        "usage_duration": db_user.usage_duration,
        "remaining_days": calculate_remaining_days(db_user.expiry_date),
        "simultaneous_connections": db_user.simultaneous_connections,
        "is_active": db_user.is_active
    }
