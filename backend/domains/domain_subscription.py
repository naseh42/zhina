from typing import List, Dict
from backend.database import get_db
from backend.models import Domain, User
from sqlalchemy.orm import Session
from backend.utils import generate_subscription_link

def get_domain_configs(db: Session, domain_ids: List[int]) -> List[Dict]:
    """ دریافت کانفیگ‌های دامنه‌های انتخاب‌شده """
    domains = db.query(Domain).filter(Domain.id.in_(domain_ids)).all()
    configs = []
    for domain in domains:
        configs.append({
            "domain_name": domain.name,
            "config": domain.config
        })
    return configs

def create_user_subscription_link(db: Session, user_id: int, domain_ids: List[int]) -> str:
    """ ایجاد لینک سابسکریپشن برای کاربر با کانفیگ‌های دامنه‌های انتخاب‌شده """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise ValueError("کاربر یافت نشد.")

    # دریافت کانفیگ‌های دامنه‌ها
    domain_configs = get_domain_configs(db, domain_ids)

    # ایجاد لینک سابسکریپشن
    subscription_link = generate_subscription_link(user.uuid)

    # اضافه کردن کانفیگ‌های دامنه‌ها به لینک سابسکریپشن
    subscription_link += "?configs=" + ",".join([config["domain_name"] for config in domain_configs])

    return subscription_link
