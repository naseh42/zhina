from fastapi import FastAPI, Request, Response, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from pathlib import Path
import logging
import os

# ==================== تنظیمات پایه ====================
app = FastAPI(
    title="Zhina Panel",
    description="پنل مدیریت Xray",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

# ==================== تنظیمات مسیرها ====================
BASE_DIR = Path(__file__).parent.parent
TEMPLATE_DIR = "/var/lib/zhina/frontend/templates"
STATIC_DIR = "/var/lib/zhina/frontend/static"

# ==================== پیکربندی تمپلیت و استاتیک ====================
templates = Jinja2Templates(directory=TEMPLATE_DIR)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# ==================== CORS ====================
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ==================== احراز هویت ====================
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not utils.verify_password(password, user.hashed_password):
        return None
    return user

def create_access_token(data: dict, expires_delta: timedelta = None):
    import jwt
    from .config import settings

    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.SECRET_KEY, algorithm="HS256")
    return encoded_jwt

# ==================== مسیرهای اصلی ====================
@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """صفحه اصلی با ریدایرکت به لاگین"""
    return RedirectResponse(url="/login")

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """نمایش صفحه لاگین"""
    return templates.TemplateResponse("login.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css"
    })

@app.post("/token")
async def login(
    response: Response,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    """پردازش فرم لاگین"""
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="نام کاربری یا رمز عبور نامعتبر",
        )
    
    access_token = create_access_token(data={"sub": user.username})
    
    response.set_cookie(
        key="access_token",
        value=f"Bearer {access_token}",
        httponly=True,
        max_age=1800,
        path="/",
        samesite="lax"
    )
    return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)

# ==================== مسیرهای احراز هویت شده ====================
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, token: str = Depends(oauth2_scheme)):
    """داشبورد مدیریتی"""
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css"
    })

@app.get("/users", response_class=HTMLResponse)
async def users(request: Request, token: str = Depends(oauth2_scheme)):
    """مدیریت کاربران"""
    return templates.TemplateResponse("users.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css"
    })

@app.get("/settings", response_class=HTMLResponse)
async def settings(request: Request, token: str = Depends(oauth2_scheme)):
    """تنظیمات سیستم"""
    return templates.TemplateResponse("settings.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css"
    })

# ==================== مسیرهای API ====================
@app.get("/health")
async def health_check():
    """بررسی سلامت سرویس"""
    return {
        "status": "OK",
        "timestamp": datetime.now().isoformat(),
        "version": "1.0.0"
    }

# ==================== اجرای سرور ====================
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8001,
        reload=True,
        log_level="debug"
    )
