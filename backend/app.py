from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from pathlib import Path
import logging
import os

# ==================== تنظیمات اولیه ====================
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

# ==================== مسیرهای اصلی ====================
@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return RedirectResponse(url="/login")

@app.route("/login", methods=["GET", "POST"])
async def login_handler(request: Request):
    if request.method == "GET":
        return templates.TemplateResponse("login.html", {
            "request": request,
            "css_url": "/static/css/futuristic.css"
        })
    
    form_data = await request.form()
    username = form_data.get("username")
    password = form_data.get("password")
    
    # TODO: پیاده‌سازی منطق احراز هویت
    return RedirectResponse("/dashboard", status_code=status.HTTP_303_SEE_OTHER)

@app.post("/token")
async def login_token(
    response: Response,
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    # پیاده‌سازی موجود برای توکن
    pass

# ==================== مسیرهای احراز هویت شده ====================
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css"
    })

@app.get("/users", response_class=HTMLResponse)
async def users(request: Request):
    return templates.TemplateResponse("users.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css"
    })

# ==================== مدیریت خطاها ====================
@app.exception_handler(405)
async def method_not_allowed(request: Request, exc):
    return JSONResponse(
        {"detail": f"متد {request.method} برای این آدرس پشتیبانی نمی‌شود"},
        status_code=405
    )

# ==================== اجرای سرور ====================
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8001,
        log_level="debug"
    )
