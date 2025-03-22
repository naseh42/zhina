import secrets
import string
from datetime import datetime, timedelta

def generate_uuid() -> str:
    """ تولید یک UUID تصادفی """
    return secrets.token_hex(16)

def generate_random_string(length: int = 10) -> str:
    """ تولید یک رشته تصادفی """
    chars = string.ascii_letters + string.digits
    return ''.join(secrets.choice(chars) for _ in range(length))

def calculate_traffic_usage(total_traffic: int, used_traffic: int) -> float:
    """ محاسبه درصد ترافیک مصرفی """
    if total_traffic == 0:
        return 0
    return (used_traffic / total_traffic) * 100

def calculate_remaining_days(expiry_date: datetime) -> int:
    """ محاسبه تعداد روزهای باقی‌مانده تا انقضا """
    if not expiry_date:
        return 0
    remaining = expiry_date - datetime.now()
    return remaining.days

def generate_qr_code(data: str) -> str:
    """ تولید QR Code از داده‌های ورودی """
    # این تابع می‌تونه با استفاده از کتابخانه‌هایی مثل `qrcode` پیاده‌سازی بشه
    return f"QR Code for: {data}"
