from typing import Dict, Optional
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from backend.models import User, Subscription
from backend.database import get_db
from backend.utils import (
    generate_subscription_link,
    calculate_remaining_days,
    format_bytes
)
from backend.config import settings
import logging

logger = logging.getLogger(__name__)

def get_user_subscription_link(db: Session, user_id: int) -> Optional[str]:
    """
    دریافت لینک اشتراک‌گذاری کاربر
    
    Args:
        db: Session دیتابیس
        user_id: آیدی کاربر
        
    Returns:
        str: لینک اشتراک‌گذاری یا None اگر کاربر وجود نداشت
    """
    try:
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            logger.warning(f"لینک سابسکریپشن - کاربر {user_id} یافت نشد")
            return None

        subscription = db.query(Subscription)\
                       .filter(Subscription.user_id == user_id)\
                       .order_by(Subscription.created_at.desc())\
                       .first()

        protocol = subscription.protocol if subscription else "vmess"
        return generate_subscription_link(
            domain=settings.DOMAIN,
            uuid=db_user.uuid,
            protocol=protocol
        )

    except Exception as e:
        logger.error(f"خطا در تولید لینک سابسکریپشن: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="خطا در تولید لینک اشتراک"
        )

def get_user_subscription_info(db: Session, user_id: int) -> Dict:
    """
    دریافت اطلاعات کامل سابسکریپشن کاربر
    
    Args:
        db: Session دیتابیس
        user_id: آیدی کاربر
        
    Returns:
        Dict: اطلاعات سابسکریپشن
        
    Raises:
        HTTPException: اگر کاربر یافت نشد
    """
    try:
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="کاربر مورد نظر یافت نشد"
            )

        subscription = db.query(Subscription)\
                       .filter(Subscription.user_id == user_id)\
                       .order_by(Subscription.created_at.desc())\
                       .first()

        return {
            "user": {
                "username": db_user.username,
                "uuid": db_user.uuid
            },
            "subscription": {
                "data_limit": format_bytes(subscription.data_limit),
                "used_data": format_bytes(subscription.used_data),
                "remaining_data": format_bytes(
                    subscription.data_limit - subscription.used_data
                ),
                "expiry_date": subscription.expiry_date,
                "remaining_days": calculate_remaining_days(
                    subscription.expiry_date
                ),
                "max_connections": subscription.max_connections,
                "status": "active" if (
                    subscription and 
                    subscription.is_active and
                    calculate_remaining_days(subscription.expiry_date) > 0
                ) else "inactive"
            }
        }

    except Exception as e:
        logger.error(f"خطا در دریافت اطلاعات سابسکریپشن: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="خطای داخلی سرور"
        )
