from pydantic import BaseModel
from typing import Dict

class LanguageSettings(BaseModel):
    available_languages: Dict[str, str] = {
        "fa": "فارسی",
        "en": "English"
    }
    default_language: str = "fa"

    def get_language_name(self, language_code: str) -> str:
        """ دریافت نام زبان بر اساس کد زبان """
        return self.available_languages.get(language_code, "فارسی")

    def set_default_language(self, language_code: str):
        """ تنظیم زبان پیش‌فرض """
        if language_code in self.available_languages:
            self.default_language = language_code
        else:
            raise ValueError("Language code not supported.")

language_settings = LanguageSettings()
