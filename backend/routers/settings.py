from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.schemas import LanguageSettings, ThemeSettings, AdvancedSettings
from backend.models import User
from backend.utils import get_password_hash, verify_password
from backend.settings import SettingsManager

router = APIRouter()

# برای دریافت اطلاعات تنظیمات فعلی (مثل زبان و تم)
@router.get("/settings")
def get_settings(db: Session = Depends(get_db)):
    settings_manager = SettingsManager(db)
    current_language = settings_manager.appearance.current_language
    current_theme = settings_manager.appearance.current_theme
    return {
        "language": current_language,
        "theme": current_theme
    }

# برای تغییر زبان
@router.put("/settings/language")
def set_language(language: LanguageSettings, db: Session = Depends(get_db)):
    settings_manager = SettingsManager(db)
    try:
        settings_manager.appearance.set_language(language.default_language)
        return {"message": "زبان با موفقیت تغییر کرد"}
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="زبان انتخابی پشتیبانی نمی‌شود"
        )

# برای تغییر تم
@router.put("/settings/theme")
def set_theme(theme: ThemeSettings, db: Session = Depends(get_db)):
    settings_manager = SettingsManager(db)
    try:
        settings_manager.appearance.set_theme(theme.default_theme)
        return {"message": "تم با موفقیت تغییر کرد"}
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="تم انتخابی پشتیبانی نمی‌شود"
        )

# برای اعمال تنظیمات پیشرفته دامنه
@router.put("/settings/advanced")
def apply_advanced_settings(settings: AdvancedSettings, db: Session = Depends(get_db)):
    settings_manager = SettingsManager(db)
    try:
        domain = settings_manager.domain_config.update_domain_config(
            settings.domain_id, settings.config_type, settings.config
        )
        return {"message": "تنظیمات پیشرفته با موفقیت اعمال شد", "domain": domain}
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="دامنه مورد نظر یافت نشد"
        )
