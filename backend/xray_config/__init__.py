# backend/xray_config/__init__.py

# ابتدا ایمپورت تنظیمات پایه
from .settings import xray_settings
from .tls_http import http_settings, tls_settings
from .protocols import (
    ProtocolType,
    protocol_settings,
    get_protocol_config,
    set_default_protocol
)

# ایمپورت مدل‌ها و توابع پایه
from .inbounds import (
    InboundCreate,
    InboundUpdate,
    create_inbound,
    update_inbound,
    delete_inbound,
    get_inbound,
    get_inbounds
)

from .subscription import (
    SubscriptionCreate,
    SubscriptionUpdate,
    create_subscription,
    update_subscription,
    delete_subscription,
    get_subscription
)

# مدیریت Lazy Import برای XrayManager
_xray_manager_instance = None

def get_xray_manager(db_session=None):
    """تابع برای دریافت نمونه XrayManager با الگوی Singleton"""
    global _xray_manager_instance
    
    if _xray_manager_instance is None:
        from .xray_manager import XrayManager
        from backend.database import SessionLocal
        
        _xray_manager_instance = XrayManager(db_session or SessionLocal())
    
    return _xray_manager_instance

# لیست صادرات ماژول
__all__ = [
    # تنظیمات
    'xray_settings',
    'http_settings',
    'tls_settings',
    'protocol_settings',
    
    # انواع داده‌ها
    'ProtocolType',
    
    # مدل‌های اینباند
    'InboundCreate',
    'InboundUpdate',
    
    # مدل‌های سابسکریپشن
    'SubscriptionCreate',
    'SubscriptionUpdate',
    
    # توابع اینباند
    'create_inbound',
    'update_inbound',
    'delete_inbound',
    'get_inbound',
    'get_inbounds',
    
    # توابع سابسکریپشن
    'create_subscription',
    'update_subscription',
    'delete_subscription',
    'get_subscription',
    
    # توابع پروتکل
    'get_protocol_config',
    'set_default_protocol',
    
    # مدیریت Xray
    'get_xray_manager'
]
