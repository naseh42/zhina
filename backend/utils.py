from passlib.context import CryptContext
from jose import jwt, JWTError
from datetime import datetime, timedelta
from typing import Optional
import secrets
import string
from backend.config import settings

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

# JWT Token
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(
        to_encode, 
        settings.SECRET_KEY, 
        algorithm=settings.JWT_ALGORITHM
    )
    return encoded_jwt

# Token Verification
def verify_token(token: str) -> Optional[str]:
    """
    Verify the JWT token for validity and return the username if valid.
    """
    try:
        payload = jwt.decode(
            token, 
            settings.SECRET_KEY, 
            algorithms=[settings.JWT_ALGORITHM]
        )
        username: str = payload.get("sub")
        if username is None:
            return None
        return username
    except JWTError:
        return None

# UUID Generation
def generate_uuid() -> str:
    return secrets.token_hex(16)

# Subscription Link
def generate_subscription_link(domain: str, uuid: str) -> str:
    return f"https://{domain}/subscription/{uuid}"

# Traffic Calculation
def calculate_traffic_usage(total_traffic: int, used_traffic: int) -> float:
    if total_traffic == 0:
        return 0
    return (used_traffic / total_traffic) * 100

# Expiry Days Calculation
def calculate_remaining_days(expiry_date: datetime) -> int:
    if not expiry_date:
        return 0
    remaining = expiry_date - datetime.now()
    return remaining.days

# Random Password
def generate_random_password(length: int = 12) -> str:
    chars = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(chars) for _ in range(length))
# QR Code Generation
def generate_qr_code(data: str) -> str:
    """
    Generate QR code image from data
    Returns: Base64 encoded image string
    """
    import qrcode
    import io
    import base64
    
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(data)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    buffered = io.BytesIO()
    img.save(buffered, format="PNG")
    return base64.b64encode(buffered.getvalue()).decode("utf-8")
# SSL Certificate Setup
   def setup_ssl(domain: str) -> bool:
       """
       تنظیم خودکار گواهی SSL برای دامنه
       Returns: True اگر موفقیت‌آمیز بود
       """
       try:
           import subprocess
           # این دستورها بستگی به تنظیمات سرور شما دارد
           result = subprocess.run([
               'certbot',
               '--nginx',
               '-d', domain,
               '--non-interactive',
               '--agree-tos',
               '--email', 'admin@example.com'  # ایمیل خود را جایگزین کنید
           ], capture_output=True, text=True)
           return "Congratulations" in result.stdout
       except Exception as e:
           print(f"Error in SSL setup: {e}")
           return False
