from fastapi import FastAPI, Depends, HTTPException, status, Request, Response, Form, WebSocket
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime, timedelta
from pathlib import Path
import logging
import sys
import psutil
import asyncio
import subprocess
import json
from typing import Dict, Any, List
from pydantic import BaseModel

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
from backend import schemas, models, utils
from backend.database import get_db, engine, Base
from backend.config import settings
from backend.xray_config.xray_manager import XrayManager
from backend.xray_config import get_xray_manager
from backend.users.user_manager import UserManager
from backend.domains.domain_manager import DomainManager
from backend.dashboard.dashboard_manager import DashboardManager

xray_manager = get_xray_manager()

# ایجاد دایرکتوری لاگ اگر وجود نداشته باشد
log_dir = Path('/opt/zhina/logs')
log_dir.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/zhina/logs/panel.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Zhina Panel",
    description="Xray Proxy Management Panel",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

TEMPLATE_DIR = "/opt/zhina/frontend/templates"
STATIC_DIR = "/opt/zhina/frontend/static"
templates = Jinja2Templates(directory=TEMPLATE_DIR)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"]
)

# مدل‌های پاسخ
class ServerStatsResponse(BaseModel):
    cpu: float
    memory: Dict[str, Any]
    disk: Dict[str, Any]
    users_online: int

class XrayConfigResponse(BaseModel):
    config: Dict[str, Any]
    status: str

@app.on_event("startup")
async def startup():
    Base.metadata.create_all(bind=engine)
    try:
        XrayManager(next(get_db())).update_xray_config()
        logger.info("Xray configuration initialized")
    except Exception as e:
        logger.error(f"Xray init error: {str(e)}")
    logger.info("Application started successfully")

@app.websocket("/ws/status")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    while True:
        try:
            xray_status = subprocess.run(
                ["systemctl", "is-active", "xray"],
                capture_output=True,
                text=True
            )
            db_status = "online" if validate_db_connection(next(get_db())) else "offline"
            await websocket.send_json({
                "xray": xray_status.stdout.strip(),
                "database": db_status,
                "timestamp": datetime.now().isoformat(),
                "users_online": get_online_users_count()
            })
            await asyncio.sleep(5)
        except Exception as e:
            logger.error(f"WebSocket error: {str(e)}")
            break

def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not utils.verify_password(password, user.hashed_password):
        return False
    return user

def validate_db_connection(db: Session):
    try:
        db.execute(text("SELECT 1"))
        db.commit()
        return True
    except Exception as e:
        db.rollback()
        logger.error(f"Database connection error: {str(e)}")
        return False

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
            "error": "Invalid credentials"
        })
    access_token = utils.create_access_token(data={"sub": user.username})
    response = RedirectResponse(url="/dashboard", status_code=303)
    response.set_cookie(key="access_token", value=f"Bearer {access_token}", httponly=True)
    return response

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, db: Session = Depends(get_db)):
    stats = {
        "users": db.query(models.User).count(),
        "domains": db.query(models.Domain).count(),
        "active_nodes": db.query(models.Node).filter(models.Node.is_active == True).count(),
        "traffic": utils.get_total_traffic()
    }
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "stats": stats
    })

@app.get("/api/v1/server-stats", response_model=ServerStatsResponse)
async def server_stats(db: Session = Depends(get_db)):
    stats = {
        "cpu": psutil.cpu_percent(interval=1),
        "memory": dict(psutil.virtual_memory()._asdict()),
        "disk": dict(psutil.disk_usage('/')._asdict()),
        "users_online": get_online_users_count()
    }
    return stats

@app.post("/api/v1/users", response_model=schemas.UserResponse)
async def create_user(
    user_data: schemas.UserCreate,
    db: Session = Depends(get_db)
):
    manager = UserManager(db)
    return manager.create(user_data)

@app.post("/api/v1/domains", response_model=schemas.DomainResponse)
async def add_domain)
    domain_data: schemas.DomainCreate,
    db: Session = Depends(get_db)
:
    manager = DomainManager(db)
    return manager.create(domain_data)

@app.get("/api/v1/xray/config", response_model=XrayConfigResponse)
async def get_xray_config(db: Session = Depends(get_db)):
    manager = XrayManager(db)
    return {
        "config": manager.get_config(),
        "status": "active"
    }

@app.on_event("startup")
@utils.repeat_every(seconds=300)
async def periodic_xray_sync():  # تغییر به async
    try:
        with next(get_db()) as db:
            manager = XrayManager(db)
            if asyncio.iscoroutinefunction(manager.update_xray_config):
                await manager.update_xray_config()
            else:
                manager.update_xray_config()
            logger.info("Periodic Xray sync completed")
    except Exception as e:
        logger.error(f"Sync failed: {str(e)}")

def get_online_users_count() -> int:
    """پیاده‌سازی موقت شمارش کاربران آنلاین"""
    return 0

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=settings.SERVER_HOST, port=settings.SERVER_PORT)
