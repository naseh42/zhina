from fastapi import FastAPI, Depends, HTTPException, Request, Response
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy.orm import Session
from datetime import datetime
import os
import logging

# ==================== تنظیمات پایه ====================
app = FastAPI(
    title="Zhina Panel",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

# ==================== تنظیمات مسیرها ====================
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

# ==================== مسیرهای اصلی ====================
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """صفحه ورود با طراحی فوتوریستیک"""
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
    """دریافت توکن با پورت 8001"""
    user = authenticate_user(form_data.username, form_data.password, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="نام کاربری یا رمز عبور نامعتبر",
        )
    
    access_token = create_access_token(data={"sub": user.username})
    
    response.set_cookie(
        key="access_token",
        value=f"Bearer {access_token}",
        httponly=True,
        max_age=1800,
        path="/",
        samesite="lax"
    )
    return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)

# ==================== مسیرهای احراز هویت شده ====================
@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request):
    """داشبورد اصلی با پورت 8001"""
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "css_url": "/static/css/futuristic.css",
        "current_time": datetime.now()
    })

# ==================== اجرای سرور ====================
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8001,  # پورت اختصاصی 8001
        log_level="debug"
    )
