from fastapi import FastAPI, Depends, HTTPException, status, Request, Response, Form
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from pathlib import Path
import logging
import sys

sys.path.append(str(Path(__file__).parent.parent))
from backend import schemas, models, utils
from backend.database import get_db, engine, Base
from backend.config import settings
from backend.xray_config import xray_settings

app = FastAPI(
    title="Zhina Panel",
    description="Xray Proxy Management Panel",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

# --- تنظیمات تمپلیت و استاتیک ---
TEMPLATE_DIR = "/var/lib/zhina/frontend/templates"
STATIC_DIR = "/var/lib/zhina/frontend/static"
templates = Jinja2Templates(directory=TEMPLATE_DIR)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# --- CORS ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- توابع کمکی ---
def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not utils.verify_password(password, user.hashed_password):
        return False
    return user

# --- روت‌ها ---
@app.on_event("startup")
async def startup():
    Base.metadata.create_all(bind=engine)

@app.get("/login", response_class=HTMLResponse)
async def show_login(request: Request):
    """نمایش فرم لاگین (GET)"""
    return templates.TemplateResponse("login.html", {"request": request})

@app.post("/login", response_class=HTMLResponse)
async def process_login(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db)
):
    """پردازش لاگین (POST)"""
    user = authenticate_user(username, password, db)
    if not user:
        return templates.TemplateResponse("login.html", {
            "request": request,
            "error": "نام کاربری یا رمز عبور اشتباه است"
        })
    
    access_token = utils.create_access_token(data={"sub": user.username})
    response = RedirectResponse(url="/dashboard", status_code=303)
    response.set_cookie(
        key="access_token",
        value=f"Bearer {access_token}",
        httponly=True,
        secure=True,
        samesite="lax",
        max_age=3600
    )
    return response

@app.post("/token")
async def api_login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """لاگین API (برای سرویس‌های خارجی)"""
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid credentials")
    return {"access_token": utils.create_access_token(data={"sub": user.username})}

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    """پنل مدیریت"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.post("/users/create")
async def create_user(request: Request):
    """ایجاد کاربر جدید"""
    return JSONResponse({"status": "success"})

@app.post("/settings/update")
async def update_settings(request: Request):
    """بروزرسانی تنظیمات"""
    return JSONResponse({"status": "updated"})

@app.get("/health")
async def health_check():
    """بررسی وضعیت سرور"""
    return {"status": "ok"}
