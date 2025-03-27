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
async def dashboard(request: Request, db: Session = Depends(get_db)):
    """پنل مدیریت"""
    stats = {
        "users": db.query(models.User).count(),
        "domains": db.query(models.Domain).count(),
        "active_nodes": db.query(models.Node).filter(models.Node.is_active == True).count()
    }
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "stats": stats
    })

# --- روت‌های مدیریت کاربران ---
@app.get("/users", response_class=HTMLResponse)
async def list_users(request: Request, db: Session = Depends(get_db)):
    """لیست تمام کاربران"""
    users = db.query(models.User).order_by(models.User.created_at.desc()).all()
    return templates.TemplateResponse("users.html", {
        "request": request,
        "users": users
    })

@app.post("/users/create")
async def create_user(
    request: Request,
    username: str = Form(...),
    email: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db)
):
    """ایجاد کاربر جدید"""
    new_user = models.User(
        username=username,
        email=email,
        hashed_password=utils.get_password_hash(password),
        created_at=datetime.utcnow()
    )
    db.add(new_user)
    db.commit()
    return RedirectResponse(url="/users", status_code=303)

# --- روت‌های مدیریت دامنه ---
@app.get("/domains", response_class=HTMLResponse)
async def list_domains(request: Request, db: Session = Depends(get_db)):
    """لیست دامنه‌ها"""
    domains = db.query(models.Domain).join(models.User).all()
    return templates.TemplateResponse("domains.html", {
        "request": request,
        "domains": domains
    })

# --- روت‌های تنظیمات ---
@app.get("/settings", response_class=HTMLResponse)
async def show_settings(request: Request, db: Session = Depends(get_db)):
    """تنظیمات سیستم"""
    settings = db.query(models.Setting).first()
    if not settings:
        settings = models.Setting()
        db.add(settings)
        db.commit()
    return templates.TemplateResponse("settings.html", {
        "request": request,
        "settings": settings
    })

@app.post("/settings/update")
async def update_settings(
    request: Request,
    language: str = Form(...),
    theme: str = Form(...),
    db: Session = Depends(get_db)
):
    """بروزرسانی تنظیمات"""
    settings = db.query(models.Setting).first()
    settings.language = language
    settings.theme = theme
    settings.updated_at = datetime.utcnow()
    db.commit()
    return RedirectResponse(url="/settings", status_code=303)

# --- روت‌های مدیریت نود ---
@app.get("/nodes", response_class=HTMLResponse)
async def list_nodes(request: Request, db: Session = Depends(get_db)):
    """لیست نودها"""
    nodes = db.query(models.Node).filter(models.Node.is_active == True).all()
    return templates.TemplateResponse("nodes.html", {
        "request": request,
        "nodes": nodes
    })

# --- روت‌های اینباند ---
@app.get("/inbounds", response_class=HTMLResponse)
async def list_inbounds(request: Request, db: Session = Depends(get_db)):
    """لیست اینباندها"""
    inbounds = db.query(models.Inbound).all()
    return templates.TemplateResponse("inbounds.html", {
        "request": request,
        "inbounds": inbounds
    })

# --- سلامت سیستم ---
@app.get("/health")
async def health_check(db: Session = Depends(get_db)):
    """بررسی وضعیت سرور و دیتابیس"""
    try:
        db.execute("SELECT 1")
        return {"status": "ok", "database": "connected"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
