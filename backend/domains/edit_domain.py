from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, validator
from typing import Optional, Dict
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import Domain
from backend.utils import get_current_user
from backend import schemas

router = APIRouter(prefix="/api/domains", tags=["Domains"])

class DomainUpdate(BaseModel):
    name: Optional[str] = None
    type: Optional[str] = None
    config: Optional[Dict] = None
    description: Optional[Dict] = None

    @validator("name")
    def validate_name(cls, value):
        if value and len(value) < 3:
            raise ValueError("نام دامنه باید حداقل ۳ کاراکتر داشته باشد.")
        return value

    @validator("type")
    def validate_type(cls, value):
        valid_types = ["reality", "direct", "subscription", "cdn", "other"]
        if value and value not in valid_types:
            raise ValueError(f"نوع دامنه {value} معتبر نیست.")
        return value

def edit_domain_logic(db: Session, domain_id: int, domain: DomainUpdate):
    """ ویرایش دامنه (منطق اصلی) """
    db_domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not db_domain:
        return None

    if domain.name:
        db_domain.name = domain.name
    if domain.type:
        db_domain.type = domain.type
    if domain.config:
        db_domain.config = domain.config
    if domain.description:
        db_domain.description = domain.description

    db.commit()
    db.refresh(db_domain)
    return db_domain

@router.put("/{domain_id}", response_model=schemas.Domain)
async def edit_domain(
    domain_id: int,
    domain_update: DomainUpdate,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    ویرایش دامنه با شناسه مشخص
    - نیاز به احراز هویت دارد
    - فقط مالک دامنه یا ادمین می‌تواند ویرایش کند
    """
    try:
        db_domain = edit_domain_logic(db, domain_id, domain_update)
        if not db_domain:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="دامنه مورد نظر یافت نشد"
            )
        
        if db_domain.owner_id != current_user.id and not current_user.is_superuser:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="شما مجوز ویرایش این دامنه را ندارید"
            )
            
        return db_domain
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="خطای سرور در پردازش درخواست"
        )
