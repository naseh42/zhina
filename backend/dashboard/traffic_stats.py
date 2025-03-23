from typing import Dict
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session

def get_traffic_stats(db: Session) -> Dict:
    """ دریافت آمار ترافیک مصرفی """
    users = db.query(User).all()
    total_traffic_limit = sum(user.traffic_limit for user in users)
    total_traffic_used = sum(user.traffic_used for user in users)
    total_traffic_remaining = total_traffic_limit - total_traffic_used

    stats = {
        "total_traffic_limit": total_traffic_limit,
        "total_traffic_used": total_traffic_used,
        "total_traffic_remaining": total_traffic_remaining,
        "traffic_usage_percentage": (total_traffic_used / total_traffic_limit) * 100 if total_traffic_limit > 0 else 0
    }
    return stats
