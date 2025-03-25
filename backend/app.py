from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional
import logging

from backend import schemas, models, utils
from backend.database import get_db, engine, Base
from backend.config import settings
from backend.xray_config import xray_settings

# تنظیمات لاگ
logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

app = FastAPI(
    title="Zhina Panel",
    description="Xray Proxy Management Panel",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

# CORS (بدون تغییر)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# اضافه کردن route اصلی
@app.get("/", response_class=HTMLResponse)
async def root():
    return """
    <html>
        <head><title>Zhina Panel</title></head>
        <body>
            <h1>Welcome to Zhina Panel</h1>
            <p>API Docs: <a href="/docs">/docs</a></p>
        </body>
    </html>
    """

# اصلاح startup event برای مدیریت خطاهای دیتابیس
@app.on_event("startup")
async def startup():
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables initialized successfully.")
    except Exception as e:
        if "already exists" in str(e):
            logger.warning("Database tables already exist, skipping creation.")
        else:
            logger.error(f"Database initialization failed: {str(e)}")
            raise

# بقیه کدها دقیقاً مانند قبل (بدون تغییر)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def authenticate_user(username: str, password: str, db: Session):
    # ... (کدهای قبلی بدون تغییر)

@app.post("/token", response_model=schemas.Token)
async def login_for_access_token(
    # ... (کدهای قبلی بدون تغییر)
    # ... (بقیه routes دقیقاً مانند قبل)
