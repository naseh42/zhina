from pydantic import BaseModel, validator
from typing import Optional, Dict
from backend.database import get_db
from backend.models import Domain
from sqlalchemy.orm import Session

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

    if "cdn" in domain.config:
        del domain.config["cdn"]
        db.commit()
        db.refresh(domain)
        return True
    return False
