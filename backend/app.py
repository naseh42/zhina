from fastapi import FastAPI, Depends, HTTPException, status, Request, Response, Form
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

# تنظیم مسیرهای پروژه
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

# ایمپورت‌های داخلی
from backend import schemas, models, utils
from backend.database import get_db, engine, Base
from backend.config import settings
from backend.xray_config.xray_manager import XrayManager
from backend.users.user_manager import UserManager
from backend.domains.domain_manager import DomainManager
from backend.dashboard.dashboard_manager import DashboardManager
from backend.settings.settings_manager import SettingsManager

# تنظیمات لاگینگ
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

# تنظیمات تمپلیت و استاتیک
TEMPLATE_DIR = "/var/lib/zhina/frontend/templates"
STATIC_DIR = "/var/lib/zhina/frontend/static"
templates = Jinja2Templates(directory=TEMPLATE_DIR)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# توابع کمکی
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
        logger.error(f"Database error: {str(e)}")
        return False

@app.on_event("startup")
async def startup():
    Base.metadata.create_all(bind=engine)
    logger.info("Application started successfully")

# روت‌های اصلی
@app.get("/health")
async def health_check(db: Session = Depends(get_db)):
    if not validate_db_connection(db):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection failed"
        )
    return {"status": "ok", "services": ["database", "xray"]}

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
        "active_nodes": db.query(models.Node).filter(models.Node.is_active == True).count()
    }
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "stats": stats
    })

# روت‌های API جدید
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
