from typing import Dict
from backend.database import get_db
from backend.models import Domain
from sqlalchemy.orm import Session

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
    return domainρ
