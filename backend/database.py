from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from backend.config import settings
import logging

# تنظیمات لاگینگ (مطابق با app.py شما)
logger = logging.getLogger(__name__)

# استفاده از تنظیمات DATABASE_URL از config.py (همانند قبل)
SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

# تنظیمات موتور دیتابیس (بهینه‌شده برای پروژه شما)
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_pre_ping=True,  # تشخیص اتصالات قطع شده
    pool_recycle=3600,   # جلوگیری از قطعی اتصال
    pool_size=20,        # تعداد اتصالات فعال
    max_overflow=0,      # محدودیت اتصالات اضافی
    connect_args={}      # آرگومان‌های خاص دیتابیس
)

# تنظیم SessionLocal (همانند قبل)
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    expire_on_commit=False  # اضافه شده برای مدیریت بهتر session
)

Base = declarative_base()

def get_db():
    """
    تابع وابستگی برای FastAPI (دقیقاً مطابق نیازهای app.py شما)
    """
    db = SessionLocal()
    try:
        yield db
    except Exception as e:
        logger.error(f"Database error: {str(e)}")
        db.rollback()
        raise
    finally:
        db.close()
