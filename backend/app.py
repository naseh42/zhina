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
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

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
    """مستقیماً نمایش داشبورد (بدون ریدایرکت به لاگین)"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """صفحه لاگین (در صورت نیاز به دسترسی مستقیم)"""
    return templates.TemplateResponse("login.html", {"request": request})

@app.post("/token", response_model=schemas.Token)
async def login_for_access_token(
    response: Response,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    """ایجاد توکن و ریدایرکت به داشبورد"""
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
        )
    
    access_token = utils.create_access_token(
        data={"sub": user.username},
        expires_delta=timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    
    # تنظیم توکن در کوکی و ریدایرکت
    response.set_cookie(
        key="access_token",
        value=f"Bearer {access_token}",
        httponly=True,
        max_age=1800
    )
    return {"access_token": access_token, "token_type": "bearer"}

# بقیه endpointها بدون تغییر...
