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

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from backend import schemas, models, utils
from backend.database import get_db, engine, Base
from backend.config import settings
from backend.xray_config.xray_manager import XrayManager
from backend.users.user_manager import UserManager
from backend.domains.domain_manager import DomainManager
from backend.dashboard.dashboard_manager import DashboardManager

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/zhina/panel.log'),
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

TEMPLATE_DIR = "/var/lib/zhina/frontend/templates"
STATIC_DIR = "/var/lib/zhina/frontend/static"
templates = Jinja2Templates(directory=TEMPLATE_DIR)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
                "users_online": utils.get_online_users_count()
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

@app.get("/api/v1/server-stats")
async def server_stats(manager: DashboardManager = Depends(DashboardManager)):
    return manager.get_server_stats()

@app.post("/api/v1/users")
async def create_user(
    user_data: schemas.UserCreate,
    manager: UserManager = Depends(UserManager)
):
    return manager.create(user_data)

@app.post("/api/v1/domains")
async def add_domain(
    domain_data: schemas.DomainCreate,
    manager: DomainManager = Depends(DomainManager)
 ):   
    return manager.create(domain_data)

@app.get("/api/v1/xray/config")
async def get_xray_config(manager: XrayManager = Depends(XrayManager)):
    return manager.get_config()

@app.on_event("startup")
@utils.repeat_every(seconds=300)
def periodic_xray_sync():
    try:
        with next(get_db()) as db:
            XrayManager(db).update_xray_config()
            logger.info("Periodic Xray sync completed")
    except Exception as e:
        logger.error(f"Sync failed: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=settings.SERVER_HOST, port=settings.SERVER_PORT)
