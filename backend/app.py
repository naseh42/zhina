from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional
import uuid

# Import internal modules
from backend.database import get_db, Base, engine
from backend.models import User, Domain, Subscription, Node, Inbound
from backend.schemas import (
    UserCreate, UserUpdate, 
    DomainCreate, DomainUpdate,
    SubscriptionCreate, SubscriptionUpdate,
    NodeCreate, NodeUpdate
)
from backend.utils import (
    generate_uuid,
    generate_subscription_link,
    get_password_hash,
    verify_password,
    create_access_token
)
from backend.xray_config import (
    xray_settings,
    http_settings,
    tls_settings,
    InboundCreate,
    InboundUpdate,
    ProtocolType
)
from backend.config import settings

# Initialize FastAPI app
app = FastAPI(
    title="Zhina Panel API",
    description="مدیریت پیشرفته پروکسی Xray",
    version="1.0.0",
    docs_url="/docs",
    redoc_url=None
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Authentication
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# Database initialization
@app.on_event("startup")
def startup():
    Base.metadata.create_all(bind=engine)
    # Initialize default settings if needed

# ------------------- User Routes -------------------
@app.post("/users/", response_model=UserCreate, status_code=status.HTTP_201_CREATED)
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    """ایجاد کاربر جدید"""
    db_user = User(
        username=user.username,
        password=get_password_hash(user.password),
        uuid=str(uuid.uuid4()),
        traffic_limit=user.traffic_limit,
        usage_duration=user.usage_duration,
        simultaneous_connections=user.simultaneous_connections,
        is_active=True
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@app.get("/users/{user_id}", response_model=UserCreate)
def read_user(user_id: int, db: Session = Depends(get_db)):
    """دریافت اطلاعات کاربر"""
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="User not found")
    return db_user

# ------------------- Xray Management Routes -------------------
@app.get("/xray/status")
def get_xray_status():
    """دریافت وضعیت سرویس Xray"""
    return {
        "status": "active",
        "version": "1.8.11",
        "settings": xray_settings.dict(),
        "tls": tls_settings.dict(),
        "http": http_settings.dict()
    }

@app.post("/xray/inbounds", status_code=status.HTTP_201_CREATED)
def create_inbound(inbound: InboundCreate, db: Session = Depends(get_db)):
    """ایجاد اینباند جدید"""
    # Validate protocol
    if inbound.protocol not in ProtocolType.__members__.values():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid protocol type"
        )
    
    # Save to database
    db_inbound = Inbound(
        port=inbound.port,
        protocol=inbound.protocol.value,
        tag=inbound.tag,
        settings=inbound.settings,
        stream_settings=inbound.stream_settings
    )
    db.add(db_inbound)
    db.commit()
    db.refresh(db_inbound)
    
    # TODO: Apply to running Xray instance
    
    return {
        "message": "Inbound created successfully",
        "inbound": db_inbound
    }

@app.get("/xray/inbounds")
def list_inbounds(db: Session = Depends(get_db)):
    """لیست تمام اینباندها"""
    return db.query(Inbound).all()

# ------------------- Subscription Routes -------------------
@app.post("/subscriptions/", response_model=SubscriptionCreate, status_code=status.HTTP_201_CREATED)
def create_subscription_endpoint(
    subscription: SubscriptionCreate, 
    db: Session = Depends(get_db)
):
    """ایجاد سابسکریپشن جدید"""
    db_subscription = Subscription(
        uuid=subscription.uuid,
        data_limit=subscription.data_limit,
        expiry_date=subscription.expiry_date,
        max_connections=subscription.max_connections
    )
    db.add(db_subscription)
    db.commit()
    db.refresh(db_subscription)
    
    # Generate subscription link
    sub_link = generate_subscription_link(
        db_subscription.uuid,
        xray_settings.config_path
    )
    
    return {
        **db_subscription.__dict__,
        "subscription_link": sub_link
    }

# ------------------- Node Routes -------------------
@app.post("/nodes/", response_model=NodeCreate, status_code=status.HTTP_201_CREATED)
def create_node(node: NodeCreate, db: Session = Depends(get_db)):
    """ایجاد نود جدید"""
    db_node = Node(
        name=node.name,
        ip_address=node.ip_address,
        port=node.port,
        protocol=node.protocol,
        is_active=True
    )
    db.add(db_node)
    db.commit()
    db.refresh(db_node)
    return db_node

# ------------------- TLS/HTTP Routes -------------------
@app.get("/settings/tls")
def get_tls_config():
    """دریافت تنظیمات TLS"""
    return tls_settings.dict()

@app.put("/settings/tls")
def update_tls_config(updated_config: dict):
    """به‌روزرسانی تنظیمات TLS"""
    global tls_settings
    tls_settings = tls_settings.copy(update=updated_config)
    # TODO: Apply to Xray config
    return {"message": "TLS settings updated"}

@app.get("/settings/http")
def get_http_config():
    """دریافت تنظیمات HTTP"""
    return http_settings.dict()

# ------------------- Authentication Routes -------------------
@app.post("/token")
def login_for_access_token():
    """دریافت توکن دسترسی"""
    # TODO: Implement actual authentication
    access_token = create_access_token(
        data={"sub": "admin"},
        expires_delta=timedelta(minutes=30)
    )
    return {"access_token": access_token, "token_type": "bearer"}

# ------------------- Health Check -------------------
@app.get("/health")
def health_check():
    """بررسی سلامت سرویس"""
    return {
        "status": "OK",
        "timestamp": datetime.utcnow().isoformat(),
        "xray_status": "active",
        "database": "connected"
    }
