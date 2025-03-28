from sqlalchemy.orm import Session
from backend.models import User, Subscription, Inbound
from backend.database import get_db
from backend.config import settings
import logging
from .xray_manager import xray_manager

logger = logging.getLogger(__name__)

def delete_user(db: Session, user_id: int) -> bool:
    """
    حذف کامل کاربر از سیستم شامل:
    - اطلاعات کاربر
    - سابسکریپشن‌های مرتبط
    - اینباندهای اختصاصی
    - اعمال تغییرات در Xray
    
    Args:
        db: Session دیتابیس
        user_id: آیدی کاربر مورد نظر
        
    Returns:
        bool: True اگر عملیات با موفقیت انجام شد
    """
    try:
        # 1. یافتن کاربر
        db_user = db.query(User).filter(User.id == user_id).first()
        if not db_user:
            logger.warning(f"کاربر با آیدی {user_id} یافت نشد")
            return False

        # 2. حذف سابسکریپشن‌های کاربر
        subscriptions = db.query(Subscription).filter(Subscription.user_id == user_id).all()
        for sub in subscriptions:
            db.delete(sub)
            logger.info(f"سابسکریپشن کاربر {user_id} حذف شد: {sub.id}")

        # 3. حذف اینباندهای اختصاصی کاربر
        inbounds = db.query(Inbound).filter(Inbound.tag.contains(f"user_{user_id}")).all()
        for inbound in inbounds:
            db.delete(inbound)
            logger.info(f"اینباند کاربر {user_id} حذف شد: {inbound.id}")

        # 4. حذف خود کاربر
        db.delete(db_user)
        db.commit()

        # 5. اعمال تغییرات در Xray
        if settings.XRAY_AUTO_UPDATE:
            xray_manager.apply_config()

        logger.info(f"کاربر با آیدی {user_id} با موفقیت حذف شد")
        return True

    except Exception as e:
        db.rollback()
        logger.error(f"خطا در حذف کاربر {user_id}: {str(e)}")
        raise
