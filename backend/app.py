from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional
import logging
from pathlib import Path
import sys

# تنظیم مسیرهای پروژه
sys.path.append(str(Path(__file__).parent.parent))

# Importهای داخلی
from . import schemas, models, utils
from .database import get_db, engine, Base
from .config import settings
from .xray_config import xray_settings

# Initialize FastAPI
app = FastAPI(
    title="Zhina Panel",
    description="Xray Proxy Management Panel",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

# تنظیمات فایل‌های استاتیک و قالب‌ها
STATIC_DIR = "/var/lib/zhina/frontend/static"
TEMPLATE_DIR = "/var/lib/zhina/frontend/templates"

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
templates = Jinja2Templates(directory=TEMPLATE_DIR)

# تنظیمات CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# توابع کمکی
def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not utils.verify_password(password, user.hashed_password):
        return False
    return user

# راه‌اندازی پایگاه داده
@app.on_event("startup")
async def startup():
    try:
        Base.metadata.create_all(bind=engine)
        logging.info("Database tables initialized successfully.")
    except Exception as e:
        if "already exists" in str(e):
            logging.warning("Tables already exist, skipping creation.")
        else:
            logging.error(f"Database error: {str(e)}")
            raise

# مسیرها
@app.get("/", response_class=HTMLResponse)
async def serve_home(request: Request):
    """سرویس دهی صفحه اصلی داشبورد"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.post("/token", response_model=schemas.Token)
async def login_for_access_token(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    """ایجاد توکن دسترسی"""
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
        )
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = utils.create_access_token(
        data={"sub": user.username},
        expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/users/", response_model=schemas.UserCreate)
def create_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    """ایجاد کاربر جدید"""
    hashed_password = utils.get_password_hash(user.password)
    db_user = models.User(
        username=user.username,
        hashed_password=hashed_password,
        uuid=utils.generate_uuid(),
        traffic_limit=user.traffic_limit,
        usage_duration=user.usage_duration,
        simultaneous_connections=user.simultaneous_connections,
        is_active=True,
        created_at=datetime.utcnow()
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@app.get("/xray/status")
def get_xray_status():
    """دریافت وضعیت Xray"""
    return {
        "status": "active",
        "settings": xray_settings.dict()
    }

@app.get("/health")
def health_check():
    """بررسی سلامت سرویس"""
    return {
        "status": "OK",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0"
    }
