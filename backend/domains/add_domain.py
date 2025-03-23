from pydantic import BaseModel, validator
from typing import Optional, Dict
from backend.database import get_db
from backend.models import Domain
from sqlalchemy.orm import Session

class DomainCreate(BaseModel):
    name: str
    type: str  # نوع دامنه (مثلاً: reality, direct, subscription, ...)
    config: Optional[Dict] = None  # تنظیمات خاص دامنه
    description: Optional[Dict] = None  # توضیحات اضافی

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
    """ اضافه کردن دامنه جدید """
    db_domain = Domain(
        name=domain.name,
        type=domain.type,
        config=domain.config,
        description=domain.description,
        owner_id=owner_id
    )
    db.add(db_domain)
    db.commit()
    db.refresh(db_domain)
    return db_domain
