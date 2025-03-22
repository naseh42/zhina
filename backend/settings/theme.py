from pydantic import BaseModel
from typing import Dict

class ThemeSettings(BaseModel):
    available_themes: Dict[str, str] = {
        "dark": "تیره",
        "light": "روشن",
        "blue": "آبی",
        "green": "سبز"
    }
    default_theme: str = "dark"

    def get_theme_name(self, theme_code: str) -> str:
        """ دریافت نام تم بر اساس کد تم """
        return self.available_themes.get(theme_code, "تیره")

    def set_default_theme(self, theme_code: str):
        """ تنظیم تم پیش‌فرض """
        if theme_code in self.available_themes:
            self.default_theme = theme_code
        else:
            raise ValueError("Theme code not supported.")

theme_settings = ThemeSettings()
