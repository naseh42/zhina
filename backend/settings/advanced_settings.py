from pydantic import BaseModel
from typing import Dict, Optional
from backend.database import get_db
from backend.models import Domain
from sqlalchemy.orm import Session

class AdvancedSettings(BaseModel):
    domain_id: int
    config_type: str  # مثلاً: cdn, direct, reality
    config: Optional[Dict] = None  # تنظیمات خاص هر نوع

def apply_advanced_settings(db: Session, settings: AdvancedSettings):
    """ اعمال تنظیمات پیشرفته برای دامنه """
    domain = db.query(Domain).filter(Domain.id == settings.domain_id).first()
    if not domain:
        raise ValueError("دامنه یافت نشد.")

    # ذخیره تنظیمات در فیلد config دامنه
    if not domain.config:
        domain.config = {}
    domain.config[settings.config_type] = settings.config

    db.commit()
    db.refresh(domain)
    return domain
