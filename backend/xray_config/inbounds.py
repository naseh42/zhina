from pydantic import BaseModel, validator
from typing import List, Dict, Optional
from backend.database import get_db
from backend.models import Inbound
from sqlalchemy.orm import Session

class InboundCreate(BaseModel):
    port: int
    protocol: str
    settings: Optional[Dict] = None
    stream_settings: Optional[Dict] = None
    tag: Optional[str] = None

    @validator("port")
    def validate_port(cls, value):
        if value < 1 or value > 65535:
            raise ValueError("پورت باید بین ۱ تا ۶۵۵۳۵ باشد.")
        return value

    @validator("protocol")
    def validate_protocol(cls, value):
        valid_protocols = ["vmess", "vless", "trojan", "shadowsocks", "http", "socks"]
        if value not in valid_protocols:
            raise ValueError(f"پروتکل {value} معتبر نیست.")
        return value

class InboundUpdate(BaseModel):
    port: Optional[int] = None
    protocol: Optional[str] = None
    settings: Optional[Dict] = None
    stream_settings: Optional[Dict] = None
    tag: Optional[str] = None

def create_inbound(db: Session, inbound: InboundCreate):
    """ ایجاد اینباند جدید """
    db_inbound = Inbound(
        port=inbound.port,
        protocol=inbound.protocol,
        settings=inbound.settings,
        stream_settings=inbound.stream_settings,
        tag=inbound.tag
    )
    db.add(db_inbound)
    db.commit()
    db.refresh(db_inbound)
    return db_inbound

def update_inbound(db: Session, inbound_id: int, inbound: InboundUpdate):
    """ به‌روزرسانی اینباند """
    db_inbound = db.query(Inbound).filter(Inbound.id == inbound_id).first()
    if not db_inbound:
        return None

    if inbound.port:
        db_inbound.port = inbound.port
    if inbound.protocol:
        db_inbound.protocol = inbound.protocol
    if inbound.settings:
        db_inbound.settings = inbound.settings
    if inbound.stream_settings:
        db_inbound.stream_settings = inbound.stream_settings
    if inbound.tag:
        db_inbound.tag = inbound.tag

    db.commit()
    db.refresh(db_inbound)
    return db_inbound

def delete_inbound(db: Session, inbound_id: int):
    """ حذف اینباند """
    db_inbound = db.query(Inbound).filter(Inbound.id == inbound_id).first()
    if not db_inbound:
        return False

    db.delete(db_inbound)
    db.commit()
    return True
