from fastapi import FastAPI, Depends, HTTPException, Request, Response
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

# تنظیم مسیرهای پروژه
BASE_DIR = Path(__file__).parent.parent
TEMPLATE_DIR = os.path.join(BASE_DIR, "../frontend/templates")
STATIC_DIR = os.path.join(BASE_DIR, "../frontend/static")

app = FastAPI(title="Zhina Panel", version="1.0.0")

# تنظیمات Jinja2 و Static Files
templates = Jinja2Templates(directory=TEMPLATE_DIR)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# تنظیمات CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# توابع کمکی
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# --- مسیرهای اصلی ---
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """صفحه ورود"""
    return templates.TemplateResponse("login.html", {"request": request})

@app.post("/token")
async def login(
    response: Response,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    """دریافت توکن احراز هویت"""
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    access_token = create_access_token(data={"sub": user.username})
    
    # تنظیم کوکی و ریدایرکت
    response.set_cookie(
        key="access_token",
        value=f"Bearer {access_token}",
        httponly=True,
        max_age=3600,
        path="/"
    )
    return RedirectResponse(url="/dashboard", status_code=303)

# --- مسیرهای احراز هویت شده ---
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, token: str = Depends(oauth2_scheme)):
    """صفحه اصلی"""
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "css_url": "/static/css/styles.css"
    })

@app.get("/users", response_class=HTMLResponse)
async def users(request: Request, token: str = Depends(oauth2_scheme)):
    """مدیریت کاربران"""
    return templates.TemplateResponse("users.html", {"request": request})

@app.get("/settings", response_class=HTMLResponse)
async def settings(request: Request, token: str = Depends(oauth2_scheme)):
    """تنظیمات"""
    return templates.TemplateResponse("settings.html", {"request": request})

# --- مسیرهای API ---
@app.get("/health")
async def health_check():
    return {"status": "OK", "timestamp": datetime.now()}

# --- توابع پایگاه داده ---
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def authenticate_user(username: str, password: str, db: Session):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user or not verify_password(password, user.hashed_password):
        return False
    return user

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
