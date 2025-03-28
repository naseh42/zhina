from typing import Dict, List, Optional
from datetime import datetime
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from backend.models import User, Inbound, Subscription
from backend.database import get_db
from backend.utils import (
    generate_subscription_link,
    generate_qr_code,
    calculate_remaining_days,
    calculate_traffic_usage
)
from backend.config import settings
import logging

logger = logging.getLogger(__name__)

def get_user_page(db: Session, user_id: int) -> Dict:
    """
    دریافت کامل اطلاعات صفحه کاربر شامل:
    - اطلاعات پایه کاربر
    - وضعیت ترافیک
    - لینک‌های اشتراک‌گذاری
    - کانفیگ‌های فعال
    - QR Code
    
    Args:
        db: Session دیتابیس
        user_id: آیدی کاربر مورد نظر
        
    Returns:
        Dict: اطلاعات کامل صفحه کاربر
        
    Raises:
        HTTPException: اگر کاربر یافت نشد
    """
    try:
        # 1. دریافت اطلاعات کاربر
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            logger.error(f"کاربر با آیدی {user_id} یافت نشد")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="کاربر مورد نظر یافت نشد"
            )

        # 2. دریافت سابسکریپشن‌های فعال
        subscription = db.query(Subscription)\
                        .filter(Subscription.user_id == user_id)\
                        .order_by(Subscription.created_at.desc())\
                        .first()

        # 3. دریافت اینباندهای مرتبط
        inbounds = db.query(Inbound)\
                    .filter(Inbound.tag.contains(f"user_{user_id}"))\
                    .all()

        # 4. محاسبات ترافیک
        traffic_usage = calculate_traffic_usage(
            db_user.traffic_limit,
            db_user.traffic_used
        ) if db_user.traffic_limit > 0 else 0

        # 5. تولید لینک‌ها و QR Code
        subscription_link = generate_subscription_link(
            domain=settings.DOMAIN,
            uuid=db_user.uuid,
            protocol=subscription.protocol if subscription else "vmess"
        )
        
        subscription_qr = generate_qr_code(subscription_link)

        # 6. آماده‌سازی پاسخ
        return {
            "user_info": {
                "id": db_user.id,
                "username": db_user.username,
                "email": db_user.email,
                "uuid": db_user.uuid,
                "created_at": db_user.created_at,
                "is_active": db_user.is_active
            },
            "subscription_info": {
                "data_limit": subscription.data_limit if subscription else 0,
                "used_data": subscription.used_data if subscription else 0,
                "usage_percentage": traffic_usage,
                "expiry_date": subscription.expiry_date if subscription else None,
                "remaining_days": calculate_remaining_days(
                    subscription.expiry_date
                ) if subscription else 0,
                "max_connections": subscription.max_connections if subscription else 0
            },
            "connection_info": {
                "subscription_link": subscription_link,
                "subscription_qr": subscription_qr,
                "configs": [
                    {
                        "protocol": inbound.protocol,
                        "port": inbound.port,
                        "config_link": f"{settings.PANEL_URL}/config/{inbound.protocol}/{db_user.uuid}",
                        "qr_code": generate_qr_code(
                            f"{settings.PANEL_URL}/config/{inbound.protocol}/{db_user.uuid}"
                        )
                    }
                    for inbound in inbounds
                ]
            }
        }

    except Exception as e:
        logger.error(f"خطا در دریافت اطلاعات صفحه کاربر {user_id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="خطای داخلی سرور"
        )
