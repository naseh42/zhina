# فایل: backend/database.py
import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from sqlalchemy.exc import SQLAlchemyError
from backend.config import settings

logger = logging.getLogger(__name__)

# تنظیمات اتصال به دیتابیس
SQLALCHEMY_DATABASE_URL = settings.DATABASE_URL

# ایجاد موتور دیتابیس با تنظیمات پیشرفته
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    pool_size=20,
    max_overflow=0,
    pool_pre_ping=True,
    pool_recycle=3600,
    connect_args={
        "keepalives": 1,
        "keepalives_idle": 30,
        "keepalives_interval": 10,
        "keepalives_count": 5
    }
)

# ساخت session factory با تنظیمات بهینه
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    expire_on_commit=False,
    twophase=False,
    query_cls=None
)

# پایه مدل‌های دیتابیس
Base = declarative_base()

def get_db():
    """ژنراتور session برای وابستگی‌های FastAPI"""
    db = SessionLocal()
    try:
        yield db
    except SQLAlchemyError as e:
        logger.error(f"خطای دیتابیس: {str(e)}")
        db.rollback()
        raise
    finally:
        db.close()

def init_db():
    """تابع مقداردهی اولیه دیتابیس"""
    try:
        # ایجاد تمام جداول
        Base.metadata.create_all(bind=engine)
        
        # ایجاد ادمین پیش‌فرض اگر وجود نداشت
        from backend.users.user_manager import UserManager
        from backend.schemas import UserCreate
        
        with SessionLocal() as db:
            if not db.query(User).filter(User.username == "admin").first():
                admin_user = UserCreate(
                    username="admin",
                    email="admin@example.com",
                    password=settings.ADMIN_PASSWORD,
                    traffic_limit=0,
                    usage_duration=0,
                    simultaneous_connections=1
                )
                UserManager(db).create(admin_user)
                logger.info("کاربر ادمین پیش‌فرض ایجاد شد")

        logger.info("دیتابیس با موفقیت مقداردهی شد")
        
    except Exception as e:
        logger.critical(f"خطای بحرانی در مقداردهی دیتابیس: {str(e)}")
        raise

# تست اتصال هنگام ایمپورت
try:
    connection = engine.connect()
    connection.close()
    logger.info("اتصال به دیتابیس با موفقیت برقرار شد")
except Exception as e:
    logger.critical(f"خطا در اتصال به دیتابیس: {str(e)}")
    raise
