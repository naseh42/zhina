from pydantic import BaseSettings

class Settings(BaseSettings):
    # تنظیمات دیتابیس
    DATABASE_URL: str = "sqlite:///./app.db"
    
    # تنظیمات Xray
    XRAY_CONFIG_PATH: str = "/etc/xray/config.json"
    
    # تنظیمات عمومی
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = "admin123"
    LANGUAGE: str = "fa"
    THEME: str = "dark"
    ENABLE_NOTIFICATIONS: bool = True
    
    class Config:
        env_file = ".env"

settings = Settings()
