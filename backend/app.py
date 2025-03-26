from fastapi import FastAPI, Depends, HTTPException, Request, Response
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from pathlib import Path
import os
import logging

# ============ تنظیمات مسیرها ============
BASE_DIR = Path(__file__).parent.parent
TEMPLATE_DIR = "/var/lib/zhina/frontend/templates"
STATIC_DIR = "/var/lib/zhina/frontend/static"

app = FastAPI(
    title="Zhina Panel",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

# ============ تنظیمات Jinja و Static Files ============
templates = Jinja2Templates(directory=TEMPLATE_DIR)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# ============ تنظیمات CORS ============
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============ مسیرهای اصلی ============
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """صفحه ورود سیستم"""
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
    """دریافت توکن احراز هویت"""
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(status_code=401, detail="اعتبارسنجی ناموفق")
    
    access_token = create_access_token(data={"sub": user.username})
    
    response.set_cookie(
        key="access_token",
        value=f"Bearer {access_token}",
        httponly=True,
        max_age=3600,
        path="/"
    )
    return RedirectResponse(url="/dashboard", status_code=303)

# ============ مسیرهای احراز هویت شده ============
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, token: str = Depends(oauth2_scheme)):
    """صفحه اصلی داشبورد"""
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

@app.get("/domains", response_class=HTMLResponse)
async def domains(request: Request, token: str = Depends(oauth2_scheme)):
    """مدیریت دامنه‌ها"""
    return templates.TemplateResponse("domains.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css"
    })

# ============ مسیرهای API ============
@app.get("/health")
async def health_check():
    return {"status": "OK", "timestamp": datetime.now()}

# ============ توابع پایگاه داده ============
# ... (توابع موجود در فایل اصلی شما بدون تغییر باقی می‌مانند)
