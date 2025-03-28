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
import psutil
from sqlalchemy import text
from fastapi import status


sys.path.append(str(Path(__file__).parent.parent))
from backend import schemas, models, utils
from backend.database import get_db, engine, Base
from backend.config import settings
from backend.xray_config import xray_settings
from backend.managers import (
    UserManager,
    DomainManager,
    XrayManager,
    DashboardManager,
    SettingsManager
)

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

# --- مدیران جدید ---
def get_user_manager(db: Session = Depends(get_db)):
    return UserManager(db)

def get_domain_manager(db: Session = Depends(get_db)):
    return DomainManager(db)

def get_xray_manager(db: Session = Depends(get_db)):
    return XrayManager(db)

def get_dashboard_manager(db: Session = Depends(get_db)):
    return DashboardManager(db)

def get_settings_manager(db: Session = Depends(get_db)):
    return SettingsManager(db)

# --- توابع کمکی ---
def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not utils.verify_password(password, user.hashed_password):
        return False
    return user

# --- روت‌های جدید API ---
@app.get("/api/v1/server-stats")
async def get_server_stats(manager: DashboardManager = Depends(get_dashboard_manager)):
    return manager.get_server_stats()

@app.get("/api/v1/traffic-stats")
async def get_traffic_stats(manager: DashboardManager = Depends(get_dashboard_manager)):
    return manager.get_traffic_stats()

@app.post("/api/v1/domains")
async def create_domain(
    domain_data: schemas.DomainCreate,
    manager: DomainManager = Depends(get_domain_manager),
    current_user: models.User = Depends(utils.get_current_active_user)
):
    return manager.create(domain_data, current_user.id)

@app.get("/api/v1/xray/config")
async def get_xray_config(manager: XrayManager = Depends(get_xray_manager)):
    return manager.get_config()

@app.post("/api/v1/xray/inbounds")
async def create_xray_inbound(
    inbound: schemas.InboundCreate,
    manager: XrayManager = Depends(get_xray_manager),
    current_user: models.User = Depends(utils.get_current_active_user)
):
    return manager.add_inbound(inbound)

@app.put("/api/v1/xray/inbounds/{inbound_id}")
async def update_xray_inbound(
    inbound_id: int,
    inbound: schemas.InboundUpdate,
    manager: XrayManager = Depends(get_xray_manager)
):
    return manager.update_inbound(inbound_id, inbound)

@app.get("/api/v1/users")
async def get_users_list(
    detailed: bool = False,
    manager: UserManager = Depends(get_user_manager)
):
    return manager.get_user_list(detailed=detailed)

# --- روت‌های موجود (بدون تغییر) ---
@app.on_event("startup")
async def startup():
    Base.metadata.create_all(bind=engine)

@app.get("/login", response_class=HTMLResponse)
async def show_login(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@app.post("/login", response_class=HTMLResponse)
async def process_login(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db)
):
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
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid credentials")
    return {"access_token": utils.create_access_token(data={"sub": user.username})}

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, db: Session = Depends(get_db)):
    stats = {
        "users": db.query(models.User).count(),
        "domains": db.query(models.Domain).count(),
        "active_nodes": db.query(models.Node).filter(models.Node.is_active == True).count()
    }
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "stats": stats
    })

@app.get("/users", response_class=HTMLResponse)
async def list_users(request: Request, db: Session = Depends(get_db)):
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
    new_user = models.User(
        username=username,
        email=email,
        hashed_password=utils.get_password_hash(password),
        created_at=datetime.utcnow()
    )
    db.add(new_user)
    db.commit()
    return RedirectResponse(url="/users", status_code=303)

@app.get("/domains", response_class=HTMLResponse)
async def list_domains(request: Request, db: Session = Depends(get_db)):
    domains = db.query(models.Domain).join(models.User).all()
    return templates.TemplateResponse("domains.html", {
        "request": request,
        "domains": domains
    })

@app.post("/domains/add")
async def add_domain(
    request: Request,
    name: str = Form(...),
    description: str = Form(None),
    owner_id: int = Form(...),
    db: Session = Depends(get_db)
):
    new_domain = models.Domain(
        name=name,
        description={"description": description} if description else None,
        owner_id=owner_id,
        created_at=datetime.utcnow()
    )
    db.add(new_domain)
    db.commit()
    return RedirectResponse(url="/domains", status_code=303)

@app.get("/settings", response_class=HTMLResponse)
async def show_settings(request: Request, db: Session = Depends(get_db)):
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
    settings = db.query(models.Setting).first()
    settings.language = language
    settings.theme = theme
    settings.updated_at = datetime.utcnow()
    db.commit()
    return RedirectResponse(url="/settings", status_code=303)

@app.get("/nodes", response_class=HTMLResponse)
async def list_nodes(request: Request, db: Session = Depends(get_db)):
    nodes = db.query(models.Node).filter(models.Node.is_active == True).all()
    return templates.TemplateResponse("nodes.html", {
        "request": request,
        "nodes": nodes
    })

@app.get("/inbounds", response_class=HTMLResponse)
async def list_inbounds(request: Request, db: Session = Depends(get_db)):
    inbounds = db.query(models.Inbound).all()
    return templates.TemplateResponse("inbounds.html", {
        "request": request,
        "inbounds": inbounds
    })

@app.get("/health")
async def health_check(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        db.commit()
        return {"status": "ok", "database": "connected"}
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Database connection error: {str(e)}"
        )

# --- روت‌های جدید مدیریت Xray ---
@app.get("/api/v1/xray/inbounds")
async def list_xray_inbounds(
    skip: int = 0,
    limit: int = 100,
    manager: XrayManager = Depends(get_xray_manager)
):
    return manager.list_inbounds(skip=skip, limit=limit)

@app.delete("/api/v1/xray/inbounds/{inbound_id}")
async def delete_xray_inbound(
    inbound_id: int,
    manager: XrayManager = Depends(get_xray_manager)
):
    success = manager.delete_inbound(inbound_id)
    if not success:
        raise HTTPException(status_code=404, detail="Inbound not found")
    return {"status": "success"}

# --- روت‌های جدید کاربران ---
@app.post("/api/v1/users")
async def create_new_user(
    user_data: schemas.UserCreate,
    manager: UserManager = Depends(get_user_manager)
):
    return manager.create(user_data)

@app.put("/api/v1/users/{user_id}")
async def update_existing_user(
    user_id: int,
    user_data: schemas.UserUpdate,
    manager: UserManager = Depends(get_user_manager)
):
    return manager.update(user_id, user_data)

# --- روت‌های جدید دامنه ---
@app.get("/api/v1/domains")
async def get_all_domains(
    manager: DomainManager = Depends(get_domain_manager)
):
    return manager.list_by_type(None)

@app.put("/api/v1/domains/{domain_id}")
async def update_domain_settings(
    domain_id: int,
    domain_data: schemas.DomainUpdate,
    manager: DomainManager = Depends(get_domain_manager)
):
    return manager.update(domain_id, domain_data)

# --- روت‌های جدید داشبورد ---
@app.get("/api/v1/dashboard/stats")
async def get_full_dashboard_stats(
    manager: DashboardManager = Depends(get_dashboard_manager)
):
    return manager.get_full_report()

# --- روت‌های جدید تنظیمات ---
@app.get("/api/v1/settings")
async def get_current_settings(
    manager: SettingsManager = Depends(get_settings_manager)
):
    return manager.get_settings()

@app.put("/api/v1/settings")
async def update_system_settings(
    new_settings: schemas.SettingsUpdate,
    manager: SettingsManager = Depends(get_settings_manager)
):
    return manager.update_settings(new_settings)
