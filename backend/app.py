from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional

# Import internal modules
from backend.database import get_db, Base, engine
from backend.models import User, Domain, Subscription, Node, Inbound
from backend.schemas import (
    UserCreate, UserUpdate, 
    DomainCreate, DomainUpdate,
    SubscriptionCreate, SubscriptionUpdate,
    NodeCreate, NodeUpdate,
    Token, TokenData
)
from backend.utils import (
    generate_uuid,
    generate_subscription_link,
    get_password_hash,
    verify_password,
    create_access_token,
    calculate_traffic_usage,
    calculate_remaining_days
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

# ------------------- Authentication Routes -------------------
@app.post("/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

# ------------------- User Routes -------------------
@app.post("/users/", response_model=UserCreate, status_code=status.HTTP_201_CREATED)
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    hashed_password = get_password_hash(user.password)
    db_user = User(
        username=user.username,
        hashed_password=hashed_password,
        uuid=generate_uuid(),
        traffic_limit=user.traffic_limit,
        usage_duration=user.usage_duration,
        simultaneous_connections=user.simultaneous_connections,
        is_active=True
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

# ------------------- Xray Management Routes -------------------
@app.post("/xray/inbounds", status_code=status.HTTP_201_CREATED)
def create_inbound(inbound: InboundCreate, db: Session = Depends(get_db)):
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
    return {
        "message": "Inbound created successfully",
        "inbound": db_inbound
    }

# ------------------- Subscription Routes -------------------
@app.post("/subscriptions/", response_model=SubscriptionCreate)
def create_subscription(subscription: SubscriptionCreate, db: Session = Depends(get_db)):
    db_subscription = Subscription(
        uuid=subscription.uuid,
        data_limit=subscription.data_limit,
        expiry_date=subscription.expiry_date,
        max_connections=subscription.max_connections
    )
    db.add(db_subscription)
    db.commit()
    db.refresh(db_subscription)
    
    sub_link = generate_subscription_link(settings.DOMAIN, subscription.uuid)
    
    return {
        **db_subscription.__dict__,
        "subscription_link": sub_link,
        "traffic_usage": 0,
        "remaining_days": calculate_remaining_days(subscription.expiry_date)
    }

# ------------------- Health Check -------------------
@app.get("/health")
def health_check():
    return {
        "status": "OK",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0"
    }
