from fastapi import FastAPI, Depends, HTTPException, status, Request, Response
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm, HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from pathlib import Path
import logging
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
security = HTTPBearer()

def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not utils.verify_password(password, user.hashed_password):
        return False
    return user

def validate_token(token: str):
    try:
        payload = utils.decode_token(token)
        return payload
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )

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
@app.get("/login", response_class=HTMLResponse)
async def serve_login_page(request: Request, credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        token = credentials.credentials
        validate_token(token)
        return RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER)
    except HTTPException:
        return templates.TemplateResponse("login.html", {"request": request})

@app.get("/", response_class=HTMLResponse)
async def serve_home(request: Request, credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    payload = validate_token(token)
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.post("/token")
async def login_for_access_token(
    response: Response,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
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
    
    response.set_cookie(
        key="access_token",
        value=f"Bearer {access_token}",
        httponly=True,
        secure=True,  # در تولید باید True باشد
        samesite="lax",
        max_age=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    )
    
    return {"message": "Logged in successfully"}

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
def get_xray_status(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """دریافت وضعیت Xray"""
    token = credentials.credentials
    validate_token(token)
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
