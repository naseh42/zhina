from pydantic import BaseModel, Field, field_validator
from typing import List, Dict, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from backend.models import Inbound
from backend.database import get_db
from backend.config import settings
import logging

logger = logging.getLogger(__name__)

class InboundCreate(BaseModel):
    port: int = Field(..., ge=1, le=65535, description="پورت اینباند (1-65535)")
    protocol: str = Field(..., description="پروتکل اینباند")
    settings: Dict = Field(default_factory=dict, description="تنظیمات اختصاصی پروتکل")
    stream_settings: Dict = Field(default_factory=dict, description="تنظیمات جریان داده")
    tag: Optional[str] = Field(None, max_length=50, description="برچسب اینباند")
    remark: Optional[str] = Field(None, max_length=100, description="توضیحات اختیاری")

    @field_validator('protocol')
    @classmethod
    def validate_protocol(cls, v):
        valid_protocols = ["vmess", "vless", "trojan", "shadowsocks", "http", "socks"]
        if v.lower() not in valid_protocols:
            raise ValueError(f"پروتکل نامعتبر. باید یکی از این موارد باشد: {', '.join(valid_protocols)}")
        return v.lower()

    @field_validator('settings')
    @classmethod
    def validate_settings(cls, v, values):
        protocol = values.data.get('protocol')
        if protocol == 'vmess' and 'clients' not in v:
            raise ValueError("تنظیمات vmess باید شامل لیست clients باشد")
        return v

class InboundUpdate(BaseModel):
    port: Optional[int] = Field(None, ge=1, le=65535)
    protocol: Optional[str] = None
    settings: Optional[Dict] = None
    stream_settings: Optional[Dict] = None
    tag: Optional[str] = Field(None, max_length=50)
    remark: Optional[str] = Field(None, max_length=100)

    @field_validator('protocol')
    @classmethod
    def validate_protocol(cls, v):
        if v is not None:
            valid_protocols = ["vmess", "vless", "trojan", "shadowsocks", "http", "socks"]
            if v.lower() not in valid_protocols:
                raise ValueError(f"پروتکل نامعتبر. باید یکی از این موارد باشد: {', '.join(valid_protocols)}")
            return v.lower()
        return v

def create_inbound(db: Session, inbound_data: InboundCreate):
    """ایجاد اینباند جدید در دیتابیس"""
    try:
        db_inbound = Inbound(
            port=inbound_data.port,
            protocol=inbound_data.protocol,
            settings=inbound_data.settings,
            stream_settings=inbound_data.stream_settings,
            tag=inbound_data.tag,
            remark=inbound_data.remark,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
            config_path=f"/opt/xray/configs/inbound_{inbound_data.port}.json"  # تغییر مسیر به /opt
        )
        db.add(db_inbound)
        db.commit()
        db.refresh(db_inbound)
        
        if settings.XRAY_AUTO_APPLY:
            from backend.xray_config.xray_manager import apply_xray_config
            apply_xray_config()
            
        return db_inbound
    except Exception as e:
        db.rollback()
        logger.error(f"Error creating inbound: {str(e)}")
        raise

def get_inbound(db: Session, inbound_id: int):
    """دریافت اینباند بر اساس ID"""
    return db.query(Inbound).filter(Inbound.id == inbound_id).first()

def get_inbounds(db: Session, skip: int = 0, limit: int = 100):
    """دریافت لیست اینباندها"""
    return db.query(Inbound).offset(skip).limit(limit).all()

def update_inbound(db: Session, inbound_id: int, inbound_data: InboundUpdate):
    """به‌روزرسانی اینباند"""
    try:
        db_inbound = db.query(Inbound).filter(Inbound.id == inbound_id).first()
        if not db_inbound:
            return None

        update_data = inbound_data.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(db_inbound, field, value)
        
        db_inbound.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(db_inbound)
        
        if settings.XRAY_AUTO_APPLY:
            from backend.xray_config.xray_manager import apply_xray_config
            apply_xray_config()
            
        return db_inbound
    except Exception as e:
        db.rollback()
        logger.error(f"Error updating inbound: {str(e)}")
        raise

def delete_inbound(db: Session, inbound_id: int):
    """حذف اینباند"""
    try:
        db_inbound = db.query(Inbound).filter(Inbound.id == inbound_id).first()
        if not db_inbound:
            return False

        # حذف فایل کانفیگ مربوطه
        config_path = Path(f"/opt/xray/configs/inbound_{db_inbound.port}.json")  # تغییر مسیر به /opt
        if config_path.exists():
            config_path.unlink()

        db.delete(db_inbound)
        db.commit()
        
        if settings.XRAY_AUTO_APPLY:
            from backend.xray_config.xray_manager import apply_xray_config
            apply_xray_config()
            
        return True
    except Exception as e:
        db.rollback()
        logger.error(f"Error deleting inbound: {str(e)}")
        raise

# ============ توابع اضافه شده ============
def get_inbound_by_port(db: Session, port: int) -> Optional[Inbound]:  # ADDED
    """دریافت اینباند بر اساس پورت"""
    return db.query(Inbound).filter(Inbound.port == port).first()

def count_active_inbounds(db: Session) -> int:  # ADDED
    """شمارش اینباندهای فعال"""
    return db.query(Inbound).filter(Inbound.is_active == True).count()
