from pydantic import BaseModel, validator
from typing import List, Dict, Optional
from sqlalchemy.orm import Session
from backend.models import Domain, User
from backend.utils import setup_ssl, generate_subscription_link

# --- مدل‌های Pydantic ---
class DomainCreate(BaseModel):
    name: str
    type: str  # reality, direct, subscription, cdn, other
    config: Optional[Dict] = None
    description: Optional[str] = None

    @validator("name")
    def validate_name(cls, v):
        if len(v) < 3:
            raise ValueError("نام دامنه حداقل ۳ کاراکتر")
        return v

    @validator("type")
    def validate_type(cls, v):
        valid_types = ["reality", "direct", "subscription", "cdn", "other"]
        if v not in valid_types:
            raise ValueError(f"نوع دامنه نامعتبر: {v}")
        return v

class DomainUpdate(DomainCreate):
    name: Optional[str] = None
    type: Optional[str] = None

class CDNConfig(BaseModel):
    provider: str  # cloudflare, fastly, gcore
    api_key: Optional[str] = None
    settings: Optional[Dict] = None

# --- کلاس اصلی مدیریت دامنه‌ها ---
class DomainManager:
    def __init__(self, db: Session):
        self.db = db

    # --- عملیات اصلی دامنه ---
    def create(self, domain_data: DomainCreate, owner_id: int) -> Domain:
        """ایجاد دامنه جدید با SSL خودکار"""
        ssl_cert = setup_ssl(domain_data.name)
        if not ssl_cert:
            raise ValueError("خطا در دریافت گواهی SSL")

        domain = Domain(
            name=domain_data.name,
            type=domain_data.type,
            config={
                "ssl": ssl_cert,
                **domain_data.config
            },
            description=domain_data.description,
            owner_id=owner_id
        )
        
        self.db.add(domain)
        self.db.commit()
        return domain

    def update(self, domain_id: int, update_data: DomainUpdate) -> Optional[Domain]:
        """به‌روزرسانی اطلاعات دامنه"""
        domain = self.db.query(Domain).filter(Domain.id == domain_id).first()
        if not domain:
            return None

        if update_data.name:
            domain.name = update_data.name
        if update_data.type:
            domain.type = update_data.type
        if update_data.config:
            domain.config = {**domain.config, **update_data.config}
        
        self.db.commit()
        return domain

    def delete(self, domain_id: int) -> bool:
        """حذف دامنه"""
        domain = self.db.query(Domain).filter(Domain.id == domain_id).first()
        if not domain:
            return False

        self.db.delete(domain)
        self.db.commit()
        return True

    # --- مدیریت CDN ---
    def setup_cdn(self, domain_id: int, cdn_config: CDNConfig) -> Optional[Domain]:
        """تنظیم CDN برای دامنه"""
        domain = self.db.query(Domain).filter(Domain.id == domain_id).first()
        if not domain:
            return None

        domain.config["cdn"] = {
            "provider": cdn_config.provider,
            "api_key": cdn_config.api_key,
            "settings": cdn_config.settings
        }
        
        self.db.commit()
        return domain

    # --- سابسکریپشن‌ها ---
    def generate_subscription(self, user_id: int, domain_ids: List[int]) -> str:
        """تولید لینک سابسکریپشن برای کاربر"""
        user = self.db.query(User).filter(User.id == user_id).first()
        domains = self.db.query(Domain).filter(Domain.id.in_(domain_ids)).all()

        if not user or not domains:
            raise ValueError("کاربر یا دامنه یافت نشد")

        configs = [{"name": d.name, "type": d.type} for d in domains]
        return generate_subscription_link(user.uuid, configs)

    # --- سایر متدهای کاربردی ---
    def get_config(self, domain_id: int) -> Dict:
        """دریافت تنظیمات دامنه"""
        domain = self.db.query(Domain).filter(Domain.id == domain_id).first()
        return domain.config if domain else {}

    def list_by_type(self, domain_type: str) -> List[Domain]:
        """لیست دامنه‌ها بر اساس نوع"""
        return self.db.query(Domain).filter(Domain.type == domain_type).all()
