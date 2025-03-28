from typing import List, Dict, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from backend.models import User, Subscription
from backend.database import get_db
from backend.utils import (
    calculate_traffic_usage,
    calculate_remaining_days,
    format_bytes
)
from backend.config import settings
import logging

logger = logging.getLogger(__name__)

def get_user_stats(db: Session, user_id: int) -> Dict:
    """
    دریافت آمار کامل کاربر شامل:
    - اطلاعات پایه
    - مصرف ترافیک
    - وضعیت سابسکریپشن
    - محدودیت‌ها
    
    Args:
        db: Session دیتابیس
        user_id: آیدی کاربر مورد نظر
        
    Returns:
        Dict: آمار کاربر به صورت دیکشنری
        
    Raises:
        HTTPException: اگر کاربر یافت نشد
    """
    try:
        # 1. دریافت کاربر و سابسکریپشن مرتبط
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            logger.warning(f"دریافت آمار - کاربر با آیدی {user_id} یافت نشد")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="کاربر مورد نظر یافت نشد"
            )

        subscription = db.query(Subscription)\
                        .filter(Subscription.user_id == user_id)\
                        .order_by(Subscription.created_at.desc())\
                        .first()

        # 2. محاسبات ترافیک
        traffic_percentage = calculate_traffic_usage(
            db_user.traffic_limit,
            db_user.traffic_used
        ) if db_user.traffic_limit > 0 else 0

        # 3. آماده‌سازی پاسخ
        return {
            "user": {
                "id": db_user.id,
                "username": db_user.username,
                "uuid": db_user.uuid,
                "is_active": db_user.is_active,
                "created_at": db_user.created_at
            },
            "traffic": {
                "limit": format_bytes(db_user.traffic_limit),
                "used": format_bytes(db_user.traffic_used),
                "remaining": format_bytes(db_user.traffic_limit - db_user.traffic_used),
                "usage_percentage": round(traffic_percentage, 2)
            },
            "subscription": {
                "expiry_date": subscription.expiry_date if subscription else None,
                "remaining_days": calculate_remaining_days(
                    subscription.expiry_date
                ) if subscription else 0,
                "max_connections": subscription.max_connections if subscription else 0,
                "is_active": subscription.is_active if subscription else False
            },
            "system": {
                "last_activity": db_user.last_activity,
                "ip_address": db_user.last_ip
            }
        }

    except Exception as e:
        logger.error(f"خطا در دریافت آمار کاربر {user_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="خطای داخلی سرور در دریافت آمار کاربر"
        )

def get_all_users_stats(db: Session) -> List[Dict]:
    """
    دریافت آمار خلاصه تمام کاربران سیستم
    
    Args:
        db: Session دیتابیس
        
    Returns:
        List[Dict]: لیست آمار تمام کاربران
    """
    try:
        users = db.query(User).all()
        stats_list = []
        
        for user in users:
            subscription = db.query(Subscription)\
                            .filter(Subscription.user_id == user.id)\
                            .order_by(Subscription.created_at.desc())\
                            .first()
            
            stats_list.append({
                "id": user.id,
                "username": user.username,
                "uuid": user.uuid,
                "traffic": {
                    "used": format_bytes(user.traffic_used),
                    "limit": format_bytes(user.traffic_limit),
                    "percentage": round(calculate_traffic_usage(
                        user.traffic_limit,
                        user.traffic_used
                    ), 2) if user.traffic_limit > 0 else 0
                },
                "subscription": {
                    "remaining_days": calculate_remaining_days(
                        subscription.expiry_date
                    ) if subscription else 0,
                    "status": "active" if (
                        subscription and 
                        subscription.is_active and
                        calculate_remaining_days(subscription.expiry_date) > 0
                    ) else "inactive"
                },
                "last_seen": user.last_activity
            })
        
        return stats_list

    except Exception as e:
        logger.error(f"خطا در دریافت آمار تمام کاربران: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="خطای داخلی سرور در دریافت آمار کاربران"
        )
