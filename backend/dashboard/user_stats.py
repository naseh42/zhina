from typing import Dict, List
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session

def get_user_stats(db: Session) -> Dict:
    """ دریافت آمار کاربران """
    users = db.query(User).all()
    stats = {
        "total_users": len(users),
        "online_users": len([user for user in users if user.is_online]),
        "offline_users": len([user for user in users if not user.is_online and user.is_active]),
        "inactive_users": len([user for user in users if not user.is_active])
    }
    return stats

def get_user_list(db: Session) -> List[Dict]:
    """ دریافت لیست کاربران با جزئیات """
    users = db.query(User).all()
    return [
        {
            "id": user.id,
            "name": user.name,
            "uuid": user.uuid,
            "traffic_limit": user.traffic_limit,
            "traffic_used": user.traffic_used,
            "usage_duration": user.usage_duration,
            "remaining_days": calculate_remaining_days(user.expiry_date),
            "simultaneous_connections": user.simultaneous_connections,
            "is_active": user.is_active,
            "is_online": user.is_online
        }
        for user in users
    ]
