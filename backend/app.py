from fastapi import FastAPI, Depends, HTTPException, status, Request, Response
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
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

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not utils.verify_password(password, user.hashed_password):
        return False
    return user

@app.on_event("startup")
async def startup():
    try:
        Base.metadata.create_all(bind=engine)
        logging.info("Database tables initialized successfully.")
    except Exception as e:
        logging.error(f"Database error: {str(e)}")
        raise

@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request})

@app.get("/login")
async def login_form_submission(
    request: Request,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    user = authenticate_user(form_data.username, form_data.password, db)
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
        secure=False,
        samesite="none",
        max_age=3600,
        path="/",
        domain=None
    )
    return response

@app.get("/token")
async def get_token(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials"
        )
    
    access_token = utils.create_access_token(data={"sub": user.username})
    return {
        "access_token": access_token,
        "token_type": "bearer"
    }

@app.get("/", response_class=HTMLResponse)
async def home(request: Request, token: str = Depends(oauth2_scheme)):
    return RedirectResponse(url="/dashboard")

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, token: str = Depends(oauth2_scheme)):
    user = utils.verify_token(token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "css_url": "/static/css/footer.css"
    })

@app.get("/users", response_class=HTMLResponse)
async def users(request: Request, token: str = Depends(oauth2_scheme)):
    return templates.TemplateResponse("users.html", {"request": request})

@app.get("/settings", response_class=HTMLResponse)
async def settings(request: Request, token: str = Depends(oauth2_scheme)):
    return templates.TemplateResponse("settings.html", {"request": request})

@app.get("/domains", response_class=HTMLResponse)
async def domains(request: Request, token: str = Depends(oauth2_scheme)):
    return templates.TemplateResponse("domains.html", {"request": request})

@app.get("/xray/status")
async def xray_status(token: str = Depends(oauth2_scheme)):
    return {"status": "active", "config": xray_settings.dict()}

@app.get("/health")
async def health_check():
    return {"status": "ok"}
