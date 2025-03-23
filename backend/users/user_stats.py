from typing import List, Dict
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session
from backend.utils import calculate_traffic_usage, calculate_remaining_days

def get_user_stats(db: Session, user_id: int) -> Dict:
    """ دریافت آمار کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return None

    stats = {
        "name": db_user.name,
        "uuid": db_user.uuid,
        "traffic_limit": db_user.traffic_limit,
        "traffic_used": db_user.traffic_used,
        "traffic_usage_percentage": calculate_traffic_usage(db_user.traffic_limit, db_user.traffic_used),
        "usage_duration": db_user.usage_duration,
        "remaining_days": calculate_remaining_days(db_user.expiry_date),
        "simultaneous_connections": db_user.simultaneous_connections,
        "is_active": db_user.is_active
    }
    return stats

def get_all_users_stats(db: Session) -> List[Dict]:
    """ دریافت آمار همه کاربران """
    users = db.query(User).all()
    stats_list = []
    for user in users:
        stats = {
            "id": user.id,
            "name": user.name,
            "uuid": user.uuid,
            "traffic_limit": user.traffic_limit,
            "traffic_used": user.traffic_used,
            "traffic_usage_percentage": calculate_traffic_usage(user.traffic_limit, user.traffic_used),
            "usage_duration": user.usage_duration,
            "remaining_days": calculate_remaining_days(user.expiry_date),
            "simultaneous_connections": user.simultaneous_connections,
            "is_active": user.is_active
        }
        stats_list.append(stats)
    return stats_list
