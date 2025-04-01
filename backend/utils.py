from passlib.context import CryptContext
from jose import jwt, JWTError
from datetime import datetime, timedelta
from typing import Optional, Callable, Any, Coroutine
import secrets
import string
import qrcode
import io
import base64
import subprocess
from pathlib import Path
import logging
import asyncio
from functools import wraps
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import text
from backend.config import settings
from backend import schemas

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Authentication
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# Logger setup
logger = logging.getLogger(__name__)

def repeat_every(seconds: float) -> Callable:
    """
    دکوراتور برای اجرای دوره‌ای یک تابع با مدیریت خطاهای بهبود یافته
    """
    def decorator(func: Callable[..., Coroutine[Any, Any, None]]) -> Callable[..., Coroutine[Any, Any, None]]:
        @wraps(func)
        async def wrapped(*args: Any, **kwargs: Any) -> None:
            while True:
                try:
                    if func is None:
                        raise ValueError("Provided function cannot be None")
                    if not asyncio.iscoroutinefunction(func):
                        raise TypeError("Decorated function must be a coroutine")
                    
                    await func(*args, **kwargs)
                except Exception as e:
                    logger.error(f"Periodic task error: {str(e)}", exc_info=True)
                    await asyncio.sleep(min(60, seconds))  # Cap retry delay at 60s
                else:
                    await asyncio.sleep(seconds)
        return wrapped
    return decorator

def get_password_hash(password: str) -> str:
    """Hash a password using bcrypt"""
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create JWT token with optional expiration"""
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(
        to_encode, 
        settings.SECRET_KEY, 
        algorithm=settings.JWT_ALGORITHM
    )

def verify_token(token: str) -> Optional[str]:
    """Verify JWT token and return username if valid"""
    try:
        payload = jwt.decode(
            token, 
            settings.SECRET_KEY, 
            algorithms=[settings.JWT_ALGORITHM]
        )
        return payload.get("sub")
    except JWTError:
        return None

async def get_current_user(token: str = Depends(oauth2_scheme)):
    """Get current user from JWT token"""
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            token, 
            settings.SECRET_KEY, 
            algorithms=[settings.JWT_ALGORITHM]
        )
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
        return schemas.User(username=username)
    except JWTError:
        raise credentials_exception

def generate_uuid() -> str:
    """Generate random UUID"""
    return str(secrets.token_hex(16))

def generate_subscription_link(domain: str, uuid: str) -> str:
    """Generate subscription link"""
    return f"https://{domain}/sub/{uuid}"

def calculate_traffic_usage(total: int, used: int) -> float:
    """Calculate traffic usage percentage"""
    return (used / total) * 100 if total > 0 else 0

def calculate_remaining_days(expiry_date: datetime) -> int:
    """Calculate days until expiration"""
    return (expiry_date - datetime.now()).days if expiry_date else 0

def generate_random_password(length: int = 12) -> str:
    """Generate secure random password"""
    chars = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(chars) for _ in range(length))

def generate_qr_code(data: str) -> str:
    """Generate base64 encoded QR code"""
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
    return base64.b64encode(buffered.getvalue()).decode()

def setup_ssl(domain: str, email: str = "admin@example.com") -> bool:
    """Setup SSL certificate using certbot"""
    try:
        result = subprocess.run([
            'certbot',
            '--nginx',
            '-d', domain,
            '--non-interactive',
            '--agree-tos',
            '--email', email,
            '--redirect'
        ], capture_output=True, text=True)
        return result.returncode == 0
    except Exception as e:
        logger.error(f"SSL Setup Error: {e}")
        return False

def restart_xray_service() -> bool:
    """Restart Xray core service"""
    try:
        result = subprocess.run(
            ["systemctl", "restart", "xray"],
            check=True
        )
        return result.returncode == 0
    except subprocess.CalledProcessError as e:
        logger.error(f"Xray restart failed: {e}")
        return False

def validate_db_connection(db) -> bool:
    """Validate database connection"""
    try:
        db.execute(text("SELECT 1"))
        return True
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        return False

def get_online_users_count() -> int:
    """Get count of online users"""
    # TODO: Replace with actual implementation
    return 0

def format_bytes(size: int) -> str:
    """Convert bytes to human readable format"""
    power = 2**10
    n = 0
    power_labels = {0: 'B', 1: 'KB', 2: 'MB', 3: 'GB', 4: 'TB'}
    while size > power and n < len(power_labels)-1:
        size /= power
        n += 1
    return f"{size:.2f} {power_labels[n]}"

def get_total_traffic() -> dict:
    """Get total traffic statistics"""
    # TODO: Implement actual traffic calculation
    return {
        "total": 0,
        "used": 0,
        "remaining": 0
    }
