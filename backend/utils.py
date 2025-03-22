import secrets
import string
from datetime import datetime, timedelta

def generate_uuid() -> str:
    """ تولید یک UUID تصادفی """
    return secrets.token_hex(16)

def generate_subscription_link(domain: str, uuid: str) -> str:
    """ تولید لینک سابسکریپشن بر اساس دامنه و UUID """
    return f"https://{domain}/subscription/{uuid}"

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
