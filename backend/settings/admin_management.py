from pydantic import BaseModel, validator
from typing import List, Optional
from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session

class AdminCreate(BaseModel):
    username: str
    password: str
    permissions: List[str] = []

    @validator("username")
    def validate_username(cls, value):
        if len(value) < 3:
            raise ValueError("نام کاربری باید حداقل ۳ کاراکتر داشته باشد.")
        return value

    @validator("password")
    def validate_password(cls, value):
        if len(value) < 8:
            raise ValueError("رمز عبور باید حداقل ۸ کاراکتر داشته باشد.")
        return value

class AdminUpdate(BaseModel):
    username: Optional[str] = None
    password: Optional[str] = None
    permissions: Optional[List[str]] = None

def create_admin(db: Session, admin: AdminCreate):
    """ ایجاد ادمین جدید """
    db_admin = User(
        username=admin.username,
        password=hash_password(admin.password),  # هش کردن پسورد
        is_admin=True,
        permissions=admin.permissions
    )
    db.add(db_admin)
    db.commit()
    db.refresh(db_admin)
    return db_admin

def update_admin(db: Session, admin_id: int, admin: AdminUpdate):
    """ به‌روزرسانی اطلاعات ادمین """
    db_admin = db.query(User).filter(User.id == admin_id).first()
    if not db_admin:
        return None

    if admin.username:
        db_admin.username = admin.username
    if admin.password:
        db_admin.password = hash_password(admin.password)  # هش کردن پسورد جدید
    if admin.permissions:
        db_admin.permissions = admin.permissions

    db.commit()
    db.refresh(db_admin)
    return db_admin

def delete_admin(db: Session, admin_id: int):
    """ حذف ادمین """
    db_admin = db.query(User).filter(User.id == admin_id).first()
    if not db_admin:
        return False

    db.delete(db_admin)
    db.commit()
    return True
