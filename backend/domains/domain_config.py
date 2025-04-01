from fastapi import APIRouter, Depends, HTTPException, status
from typing import Dict
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import Domain
from backend.utils import get_current_user
from backend import schemas

router = APIRouter(prefix="/api/domain-config", tags=["Domain Configuration"])

def get_domain_config(db: Session, domain_id: int) -> Dict:
    """ دریافت کانفیگ‌های دامنه """
    domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not domain:
        raise ValueError("دامنه یافت نشد.")
    return domain.config

def update_domain_config(db: Session, domain_id: int, config: Dict):
    """ به‌روزرسانی کانفیگ‌های دامنه """
    domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not domain:
        raise ValueError("دامنه یافت نشد.")

    domain.config = config
    db.commit()
    db.refresh(domain)
    return domain

@router.get("/{domain_id}", response_model=Dict)
async def get_domain_config_endpoint(
    domain_id: int,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    دریافت کانفیگ دامنه
    - نیاز به احراز هویت دارد
    - فقط مالک دامنه یا ادمین می‌تواند کانفیگ را مشاهده کند
    """
    try:
        domain = db.query(Domain).filter(Domain.id == domain_id).first()
        if not domain:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="دامنه مورد نظر یافت نشد"
            )
            
        if domain.owner_id != current_user.id and not current_user.is_superuser:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="شما مجوز مشاهده کانفیگ این دامنه را ندارید"
            )
            
        return get_domain_config(db, domain_id)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.put("/{domain_id}", response_model=schemas.Domain)
async def update_domain_config_endpoint(
    domain_id: int,
    config: Dict,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    به‌روزرسانی کانفیگ دامنه
    - نیاز به احراز هویت دارد
    - فقط مالک دامنه یا ادمین می‌تواند کانفیگ را تغییر دهد
    """
    try:
        domain = db.query(Domain).filter(Domain.id == domain_id).first()
        if not domain:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="دامنه مورد نظر یافت نشد"
            )
            
        if domain.owner_id != current_user.id and not current_user.is_superuser:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="شما مجوز تغییر کانفیگ این دامنه را ندارید"
            )
            
        return update_domain_config(db, domain_id, config)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
