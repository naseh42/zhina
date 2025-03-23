from typing import Dict, List
from fastapi import HTTPException
from backend.database import get_db
from backend.models import User, Inbound
from sqlalchemy.orm import Session
from backend.utils import generate_subscription_link, generate_qr_code

def get_user_page(db: Session, user_id: int, domain: str) -> Dict:
    """ دریافت اطلاعات صفحه کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد.")

    # دریافت لیست اینباندهای متصل به کاربر
    inbounds = db.query(Inbound).filter(Inbound.user_id == user_id).all()

    # تولید لینک سابسکریپشن
    subscription_link = generate_subscription_link(domain, db_user.uuid)

    # تولید QR Code برای لینک سابسکریپشن
    subscription_qr_code = generate_qr_code(subscription_link)

    # تولید لیست کانفیگ‌ها
    configs = []
    for inbound in inbounds:
        config_link = f"https://{domain}/config/{inbound.protocol}/{db_user.uuid}"
        configs.append({
            "protocol": inbound.protocol,
            "port": inbound.port,
            "config_link": config_link
        })

    return {
        "name": db_user.name,
        "uuid": db_user.uuid,
        "traffic_limit": db_user.traffic_limit,
        "traffic_used": db_user.traffic_used,
        "usage_duration": db_user.usage_duration,
        "remaining_days": calculate_remaining_days(db_user.expiry_date),
        "simultaneous_connections": db_user.simultaneous_connections,
        "is_active": db_user.is_active,
        "subscription_link": subscription_link,
        "subscription_qr_code": subscription_qr_code,
        "configs": configs
    }
