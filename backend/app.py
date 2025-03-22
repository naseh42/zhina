from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from backend.routers import users_router, domains_router, subscriptions_router, settings_router, xray_router, panel_router
from backend.config import settings
from backend.utils.logger import setup_logger
from backend.database import engine, Base
from backend.utils.time_utils import get_current_time, format_datetime
import os

# ایجاد شیء FastAPI
app = FastAPI(
    title=settings.API_TITLE,
    description=settings.API_DESCRIPTION,
    version=settings.API_VERSION
)

# تنظیم مسیر تمپلت‌ها
templates = Jinja2Templates(directory="backend/templates")

# اضافه کردن فایل‌های استاتیک
app.mount("/static", StaticFiles(directory="backend/static"), name="static")

# افزودن Middleware‌ها
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
    allow_headers=["*"],
)

# ایجاد جداول پایگاه داده
Base.metadata.create_all(bind=engine)

# تنظیم لاگر
logger = setup_logger()

# رویدادهای startup و shutdown
@app.on_event("startup")
async def startup_event():
    current_time = get_current_time()
    logger.info(f"🚀 Application started at {format_datetime(current_time)}")
    ensure_directory_exists("backend/static")
    favicon_path = "backend/static/favicon.ico"
    if not os.path.exists(favicon_path):
        with open(favicon_path, "w") as f:
            pass

@app.on_event("shutdown")
async def shutdown_event():
    current_time = get_current_time()
    logger.info(f"🛑 Application shutting down at {format_datetime(current_time)}")

# اضافه کردن روت‌ها
app.include_router(users_router, prefix="/users", tags=["Users"])
app.include_router(domains_router, prefix="/domains", tags=["Domains"])
app.include_router(subscriptions_router, prefix="/subscriptions", tags=["Subscriptions"])
app.include_router(settings_router, prefix="/settings", tags=["Settings"])
app.include_router(xray_router, prefix="/xray", tags=["Xray"])
app.include_router(panel_router, prefix="/panel", tags=["Panel"])

# مدیریت خطاهای عمومی
@app.exception_handler(404)
async def not_found_exception_handler(request: Request, exc):
    logger.warning(f"404 Error: {request.url} not found.")
    return JSONResponse(
        status_code=404,
        content={"message": "The requested resource was not found."},
    )

@app.exception_handler(422)
async def validation_exception_handler(request: Request, exc):
    logger.error(f"422 Validation Error at {request.url}: {exc.errors()}")
    return JSONResponse(
        status_code=422,
        content={"message": "Validation error occurred.", "details": exc.errors()},
    )

# Middleware لاگ‌برداری
@app.middleware("http")
async def log_request_details(request: Request, call_next):
    logger.debug(f"Headers: {request.headers}")
    logger.debug(f"URL: {request.url}")
    response = await call_next(request)
    logger.debug(f"Response status: {response.status_code}")
    return response
