from pydantic import BaseModel, validator
from typing import Optional
from passlib.context import CryptContext

# تنظیمات هش کردن پسورد
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str
    confirm_password: str

    @validator("new_password")
    def validate_new_password(cls, value):
        if len(value) < 8:
            raise ValueError("رمز عبور باید حداقل ۸ کاراکتر داشته باشد.")
        return value

    @validator("confirm_password")
    def validate_confirm_password(cls, value, values):
        if "new_password" in values and value != values["new_password"]:
            raise ValueError("رمز عبور جدید و تأیید آن مطابقت ندارند.")
        return value

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """ بررسی تطابق پسورد ورودی با پسورد هش‌شده """
    return pwd_context.verify(plain_password, hashed_password)

def hash_password(password: str) -> str:
    """ هش کردن پسورد """
    return pwd_context.hash(password)
