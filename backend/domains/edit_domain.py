from pydantic import BaseModel, validator
from typing import Optional, Dict
from backend.database import get_db
from backend.models import Domain
from sqlalchemy.orm import Session

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

def edit_domain(db: Session, domain_id: int, domain: DomainUpdate):
    """ ویرایش دامنه """
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
