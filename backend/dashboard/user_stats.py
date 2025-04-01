from fastapi import APIRouter, Depends
from typing import Dict, List
from datetime import datetime
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session
from pydantic import BaseModel

router = APIRouter()

# تعریف مدل‌های Pydantic برای پاسخ‌ها
class UserStatsResponse(BaseModel):
    total_users: int
    online_users: int
    offline_users: int
    inactive_users: int

class UserListItem(BaseModel):
    id: int
    name: str
    uuid: str
    traffic_limit: float
    traffic_used: float
    usage_duration: float
    remaining_days: int
    simultaneous_connections: int
    is_active: bool
    is_online: bool

def calculate_remaining_days(expiry_date: datetime) -> int:
    """محاسبه روزهای باقیمانده تا انقضا"""
    if not expiry_date:
        return 0
    remaining = expiry_date - datetime.now()
    return remaining.days if remaining.days > 0 else 0

@router.get("/stats", response_model=UserStatsResponse)
async def user_stats_endpoint(db: Session = Depends(get_db)):
    """Endpoint برای دریافت آمار کاربران"""
    users = db.query(User).all()
    stats = {
        "total_users": len(users),
        "online_users": len([user for user in users if user.is_online]),
        "offline_users": len([user for user in users if not user.is_online and user.is_active]),
        "inactive_users": len([user for user in users if not user.is_active])
    }
    return UserStatsResponse(**stats)

@router.get("/list", response_model=List[UserListItem])
async def user_list_endpoint(db: Session = Depends(get_db)):
    """Endpoint برای دریافت لیست کاربران"""
    users = db.query(User).all()
    user_list = [
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
    return [UserListItem(**user) for user in user_list]
