from pydantic import BaseModel, validator
from typing import Dict, List, Optional
from passlib.context import CryptContext
from sqlalchemy.orm import Session
from backend.models import User, Domain

# --- بخش امنیتی ---
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class SecurityManager:
    @staticmethod
    def hash_password(password: str) -> str:
        """هش کردن پسورد"""
        return pwd_context.hash(password)

    @staticmethod
    def verify_password(plain_password: str, hashed_password: str) -> bool:
        """بررسی تطابق پسورد"""
        return pwd_context.verify(plain_password, hashed_password)

# --- بخش مدیریت ادمین ---
class AdminCreate(BaseModel):
    username: str
    password: str
    permissions: List[str] = []

    @validator("username")
    def validate_username(cls, v):
        if len(v) < 3:
            raise ValueError("نام کاربری حداقل ۳ کاراکتر")
        return v

    @validator("password")
    def validate_password(cls, v):
        if len(v) < 8:
            raise ValueError("رمز عبور حداقل ۸ کاراکتر")
        return v

class AdminManager:
    def __init__(self, db: Session):
        self.db = db
        self.security = SecurityManager()

    def create_admin(self, data: AdminCreate) -> User:
        """ایجاد ادمین جدید"""
        admin = User(
            username=data.username,
            password=self.security.hash_password(data.password),
            is_admin=True,
            permissions=data.permissions
        )
        self.db.add(admin)
        self.db.commit()
        return admin

    def update_admin(self, admin_id: int, new_data: dict) -> Optional[User]:
        """به‌روزرسانی ادمین"""
        admin = self.db.query(User).filter(User.id == admin_id, User.is_admin == True).first()
        if not admin:
            return None

        if 'password' in new_data:
            new_data['password'] = self.security.hash_password(new_data['password'])
        
        for key, value in new_data.items():
            setattr(admin, key, value)
        
        self.db.commit()
        return admin

# --- بخش تنظیمات پیشرفته ---
class DomainConfigManager:
    def __init__(self, db: Session):
        self.db = db

    def update_domain_config(self, domain_id: int, config_type: str, config: dict) -> Optional[Domain]:
        """به‌روزرسانی تنظیمات دامنه"""
        domain = self.db.query(Domain).filter(Domain.id == domain_id).first()
        if not domain:
            return None

        if not domain.config:
            domain.config = {}
        
        domain.config[config_type] = config
        self.db.commit()
        return domain

# --- بخش تنظیمات ظاهری ---
class AppearanceSettings:
    def __init__(self):
        self.languages = {
            "fa": "فارسی",
            "en": "English"
        }
        self.themes = {
            "dark": "تیره",
            "light": "روشن"
        }
        self.current_language = "fa"
        self.current_theme = "dark"

    def set_language(self, lang_code: str):
        """تغییر زبان سیستم"""
        if lang_code in self.languages:
            self.current_language = lang_code
        else:
            raise ValueError("زبان انتخاب شده پشتیبانی نمی‌شود")

    def set_theme(self, theme_code: str):
        """تغییر تم سیستم"""
        if theme_code in self.themes:
            self.current_theme = theme_code
        else:
            raise ValueError("تم انتخاب شده پشتیبانی نمی‌شود")

# --- مدیر کل تنظیمات ---
class SettingsManager:
    def __init__(self, db: Session):
        self.db = db
        self.admin = AdminManager(db)
        self.domain_config = DomainConfigManager(db)
        self.appearance = AppearanceSettings()
        self.security = SecurityManager()
