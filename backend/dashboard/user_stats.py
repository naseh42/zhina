from fastapi import APIRouter, Depends
from typing import Dict, List
from datetime import datetime
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session

router = APIRouter()

def calculate_remaining_days(expiry_date: datetime) -> int:
    """محاسبه روزهای باقیمانده تا انقضا"""
    if not expiry_date:
        return 0
    remaining = expiry_date - datetime.now()
    return remaining.days if remaining.days > 0 else 0

@router.get("/stats")
async def user_stats_endpoint(db: Session = Depends(get_db)):
    """Endpoint برای دریافت آمار کاربران"""
    return get_user_stats(db)

@router.get("/list")
async def user_list_endpoint(db: Session = Depends(get_db)):
    """Endpoint برای دریافت لیست کاربران"""
    return get_user_list(db)

def get_user_stats(db: Session) -> Dict:
    """دریافت آمار کاربران"""
    users = db.query(User).all()
    stats = {
        "total_users": len(users),
        "online_users": len([user for user in users if user.is_online]),
        "offline_users": len([user for user in users if not user.is_online and user.is_active]),
        "inactive_users": len([user for user in users if not user.is_active])
    }
    return stats

def get_user_list(db: Session) -> List[Dict]:
    """دریافت لیست کاربران با جزئیات"""
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
