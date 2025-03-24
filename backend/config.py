from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # تنظیمات دیتابیس
    DATABASE_URL: str = "sqlite:///./default.db"
    
    # تنظیمات Xray
    XRAY_CONFIG_PATH: str = "/etc/xray/default_config.json"
    
    # تنظیمات عمومی
    ADMIN_USERNAME: str = "default_admin"
    ADMIN_PASSWORD: str = "default_password"
    LANGUAGE: str = "en"
    THEME: str = "light"
    ENABLE_NOTIFICATIONS: bool = False

    class Config:
        env_file = ".env"

settings = Settings()
