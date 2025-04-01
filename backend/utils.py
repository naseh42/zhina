from passlib.context import CryptContext
from jose import jwt, JWTError
from datetime import datetime, timedelta
from typing import Optional
import secrets
import string
import qrcode
import io
import base64
import subprocess
from pathlib import Path
import logging
from backend.config import settings

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def get_password_hash(password: str) -> str:
    """Hash a password using bcrypt"""
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    return pwd_context.verify(plain_password, hashed_password)

# JWT Token
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

# UUID Generation
def generate_uuid() -> str:
    """Generate random UUID"""
    return str(secrets.token_hex(16))

# Subscription Management
def generate_subscription_link(domain: str, uuid: str) -> str:
    """Generate subscription link"""
    return f"https://{domain}/sub/{uuid}"

def calculate_traffic_usage(total: int, used: int) -> float:
    """Calculate traffic usage percentage"""
    return (used / total) * 100 if total > 0 else 0

def calculate_remaining_days(expiry_date: datetime) -> int:
    """Calculate days until expiration"""
    return (expiry_date - datetime.now()).days if expiry_date else 0

# Password Generation
def generate_random_password(length: int = 12) -> str:
    """Generate secure random password"""
    chars = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(chars) for _ in range(length))

# QR Code Generation
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

# SSL Certificate
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

# System Utilities
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

# Database Utilities
def validate_db_connection(db) -> bool:
    """Validate database connection"""
    try:
        db.execute(text("SELECT 1"))
        return True
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        return False

# User Utilities
def get_online_users_count() -> int:
    """Get count of online users (mock implementation)"""
    # TODO: Replace with actual logic
    return 0
