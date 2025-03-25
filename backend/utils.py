import secrets
import string
from datetime import datetime, timedelta
from passlib.context import CryptContext
from jose import jwt
from typing import Optional
from backend.config import settings

# تنظیمات رمزنگاری
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def generate_uuid() -> str:
    """تولید یک UUID تصادفی"""
    return secrets.token_hex(16)

def generate_subscription_link(domain: str, uuid: str) -> str:
    """تولید لینک سابسکریپشن بر اساس دامنه و UUID"""
    return f"https://{domain}/subscription/{uuid}"

def calculate_traffic_usage(total_traffic: int, used_traffic: int) -> float:
    """محاسبه درصد ترافیک مصرفی"""
    if total_traffic == 0:
        return 0
    return (used_traffic / total_traffic) * 100

def calculate_remaining_days(expiry_date: datetime) -> int:
    """محاسبه تعداد روزهای باقی‌مانده تا انقضا"""
    if not expiry_date:
        return 0
    remaining = expiry_date - datetime.now()
    return remaining.days

def get_password_hash(password: str) -> str:
    """هش کردن رمز عبور با الگوریتم bcrypt"""
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """بررسی تطابق رمز عبور با هش ذخیره شده"""
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """تولید توکن JWT برای احراز هویت"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm="HS256")
    return encoded_jwt

def generate_random_password(length: int = 12) -> str:
    """تولید رمز عبور تصادفی امن"""
    chars = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(chars) for _ in range(length))
