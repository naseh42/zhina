from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import OperationalError
from backend.config import settings
import time
import logging

logger = logging.getLogger(__name__)

# تنظیمات اتصال به دیتابیس
SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

# ایجاد موتور دیتابیس با تنظیمات reconnect
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_pre_ping=True,
    pool_recycle=3600
)

# ایجاد session برای تعامل با دیتابیس
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base برای مدل‌ها
Base = declarative_base()

# تابع برای دریافت session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# تابع انتظار برای اتصال به دیتابیس
def wait_for_db():
    max_retries = 5
    retry_delay = 3  # seconds
    for _ in range(max_retries):
        try:
            with engine.connect() as conn:
                return True
        except OperationalError as e:
            logger.warning(f"Database not ready, retrying... Error: {str(e)}")
            time.sleep(retry_delay)
    raise RuntimeError("Could not connect to database after retries!")

# بررسی اتصال هنگام import
wait_for_db()
