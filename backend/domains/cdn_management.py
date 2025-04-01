from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, validator
from typing import Optional, Dict
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import Domain
from backend.utils import get_current_user
from backend import schemas

router = APIRouter(prefix="/api/cdn", tags=["CDN Management"])

class CDNConfig(BaseModel):
    cdn_provider: str  # سرویس CDN (مثلاً: cloudflare, fastly, gcore)
    api_key: Optional[str] = None  # کلید API برای سرویس CDN
    config: Optional[Dict] = None  # تنظیمات خاص CDN

    @validator("cdn_provider")
    def validate_cdn_provider(cls, value):
        valid_providers = ["cloudflare", "fastly", "gcore"]
        if value not in valid_providers:
            raise ValueError(f"سرویس CDN {value} معتبر نیست.")
        return value

def add_cdn_domain(db: Session, domain_id: int, cdn_config: CDNConfig):
    """ اضافه کردن تنظیمات CDN به دامنه """
    domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not domain:
        return None

    # ذخیره‌سازی تنظیمات CDN
    if not domain.config:
        domain.config = {}
    domain.config["cdn"] = {
        "provider": cdn_config.cdn_provider,
        "api_key": cdn_config.api_key,
        "config": cdn_config.config
    }
    db.commit()
    db.refresh(domain)
    return domain

def update_cdn_domain(db: Session, domain_id: int, cdn_config: CDNConfig):
    """ به‌روزرسانی تنظیمات CDN دامنه """
    domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not domain:
        return None

    # به‌روزرسانی تنظیمات CDN
    if not domain.config:
        domain.config = {}
    domain.config["cdn"] = {
        "provider": cdn_config.cdn_provider,
        "api_key": cdn_config.api_key,
        "config": cdn_config.config
    }
    db.commit()
    db.refresh(domain)
    return domain

def delete_cdn_domain(db: Session, domain_id: int):
    """ حذف تنظیمات CDN از دامنه """
    domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not domain:
        return False

    if domain.config and "cdn" in domain.config:
        del domain.config["cdn"]
        db.commit()
        db.refresh(domain)
        return True
    return False

@router.post("/{domain_id}", response_model=schemas.Domain)
async def enable_cdn(
    domain_id: int,
    cdn_config: CDNConfig,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    فعال‌سازی CDN برای دامنه
    - نیاز به احراز هویت دارد
    - فقط مالک دامنه یا ادمین می‌تواند CDN را فعال کند
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
                detail="شما مجوز فعال‌سازی CDN برای این دامنه را ندارید"
            )
            
        return add_cdn_domain(db, domain_id, cdn_config)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.put("/{domain_id}", response_model=schemas.Domain)
async def update_cdn_config(
    domain_id: int,
    cdn_config: CDNConfig,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    به‌روزرسانی تنظیمات CDN دامنه
    - نیاز به احراز هویت دارد
    - فقط مالک دامنه یا ادمین می‌تواند تنظیمات را تغییر دهد
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
                detail="شما مجوز تغییر تنظیمات CDN این دامنه را ندارید"
            )
            
        return update_cdn_domain(db, domain_id, cdn_config)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.delete("/{domain_id}", status_code=status.HTTP_204_NO_CONTENT)
async def disable_cdn(
    domain_id: int,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    غیرفعال‌سازی CDN برای دامنه
    - نیاز به احراز هویت دارد
    - فقط مالک دامنه یا ادمین می‌تواند CDN را غیرفعال کند
    """
    domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not domain:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="دامنه مورد نظر یافت نشد"
        )
    
    if domain.owner_id != current_user.id and not current_user.is_superuser:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="شما مجوز غیرفعال‌سازی CDN این دامنه را ندارید"
        )
    
    if not delete_cdn_domain(db, domain_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="CDN برای این دامنه فعال نیست"
        )
    
    return {"message": "CDN با موفقیت غیرفعال شد"}
