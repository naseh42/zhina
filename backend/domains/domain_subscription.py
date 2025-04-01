from fastapi import APIRouter, Depends, HTTPException, status
from typing import List, Dict
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import Domain, User
from backend.utils import generate_subscription_link, get_current_user
from backend import schemas

router = APIRouter(prefix="/api/subscriptions", tags=["Domain Subscriptions"])

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

    domain_configs = get_domain_configs(db, domain_ids)
    subscription_link = generate_subscription_link(user.uuid)
    subscription_link += "?configs=" + ",".join([config["domain_name"] for config in domain_configs])
    return subscription_link

@router.get("/configs/", response_model=List[Dict])
async def get_domains_configs(
    domain_ids: List[int],
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    دریافت کانفیگ‌های چند دامنه
    - نیاز به احراز هویت دارد
    """
    try:
        return get_domain_configs(db, domain_ids)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.post("/generate-link/", response_model=schemas.SubscriptionLink)
async def generate_subscription_link_endpoint(
    domain_ids: List[int],
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    ایجاد لینک سابسکریپشن برای کاربر جاری
    - نیاز به احراز هویت دارد
    """
    try:
        link = create_user_subscription_link(db, current_user.id, domain_ids)
        return {"link": link}
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"خطا در ایجاد لینک: {str(e)}"
        )
