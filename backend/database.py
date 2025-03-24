from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from backend.config import settings

# تنظیمات اتصال به دیتابیس
SQLALCHEMY_DATABASE_URL = settings.database_url

# ایجاد موتور دیتابیس
engine = create_engine(settings.database_url)

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
