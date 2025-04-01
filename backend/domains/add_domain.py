from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, validator
from typing import Optional, Dict
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import Domain
from backend.utils import setup_ssl, get_current_user
from backend import schemas

router = APIRouter(prefix="/api/domains", tags=["Domains"])

class DomainCreate(BaseModel):
    name: str
    type: str
    config: Optional[Dict] = None
    description: Optional[Dict] = None

    @validator("name")
    def validate_name(cls, value):
        if len(value) < 3:
            raise ValueError("نام دامنه باید حداقل ۳ کاراکتر داشته باشد.")
        return value

    @validator("type")
    def validate_type(cls, value):
        valid_types = ["reality", "direct", "subscription", "cdn", "other"]
        if value not in valid_types:
            raise ValueError(f"نوع دامنه {value} معتبر نیست.")
        return value

def add_domain(db: Session, domain: DomainCreate, owner_id: int):
    ssl_certificate = setup_ssl(domain.name)
    if not ssl_certificate:
        raise ValueError("خطا در دریافت سرتیفیکیت SSL.")

    db_domain = Domain(
        name=domain.name,
        type=domain.type,
        config={
            "ssl_certificate": ssl_certificate,
            **(domain.config if domain.config else {})
        },
        description=domain.description,
        owner_id=owner_id
    )
    db.add(db_domain)
    db.commit()
    db.refresh(db_domain)
    return db_domain

@router.post("/add", response_model=schemas.Domain)
async def add_domain_endpoint(
    domain: DomainCreate,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user),
):
    try:
        new_domain = add_domain(db, domain, current_user.id)
        return new_domain
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
