from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import User, Domain, Subscription, Node
from backend.schemas import (
    UserCreate, UserUpdate, DomainCreate, DomainUpdate,
    SubscriptionCreate, SubscriptionUpdate, NodeCreate, NodeUpdate
)
from backend.utils import generate_uuid, generate_subscription_link
from backend.xray_config import xray_settings
from backend.settings import language_settings, theme_settings

app = FastAPI()

# تنظیمات CORS برای ارتباط با فرانت‌اند
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# روت‌های کاربران
@app.post("/users/", response_model=UserCreate)
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    """ ایجاد کاربر جدید """
    db_user = User(
        name=user.name,
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

@app.get("/users/{user_id}", response_model=UserCreate)
def read_user(user_id: int, db: Session = Depends(get_db)):
    """ دریافت اطلاعات کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    return db_user

@app.put("/users/{user_id}", response_model=UserUpdate)
def update_user(user_id: int, user: UserUpdate, db: Session = Depends(get_db)):
    """ به‌روزرسانی اطلاعات کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")

    if user.name:
        db_user.name = user.name
    if user.traffic_limit:
        db_user.traffic_limit = user.traffic_limit
    if user.usage_duration:
        db_user.usage_duration = user.usage_duration
    if user.simultaneous_connections:
        db_user.simultaneous_connections = user.simultaneous_connections

    db.commit()
    db.refresh(db_user)
    return db_user

@app.delete("/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db)):
    """ حذف کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")

    db.delete(db_user)
    db.commit()
    return {"message": "کاربر با موفقیت حذف شد"}

# روت‌های دامنه‌ها
@app.post("/domains/", response_model=DomainCreate)
def create_domain(domain: DomainCreate, db: Session = Depends(get_db)):
    """ ایجاد دامنه جدید """
    db_domain = Domain(
        name=domain.name,
        description=domain.description,
        cdn_enabled=domain.cdn_enabled
    )
    db.add(db_domain)
    db.commit()
    db.refresh(db_domain)
    return db_domain

@app.get("/domains/{domain_id}", response_model=DomainCreate)
def read_domain(domain_id: int, db: Session = Depends(get_db)):
    """ دریافت اطلاعات دامنه """
    db_domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not db_domain:
        raise HTTPException(status_code=404, detail="دامنه یافت نشد")
    return db_domain

@app.put("/domains/{domain_id}", response_model=DomainUpdate)
def update_domain(domain_id: int, domain: DomainUpdate, db: Session = Depends(get_db)):
    """ به‌روزرسانی اطلاعات دامنه """
    db_domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not db_domain:
        raise HTTPException(status_code=404, detail="دامنه یافت نشد")

    if domain.name:
        db_domain.name = domain.name
    if domain.description:
        db_domain.description = domain.description
    if domain.cdn_enabled is not None:
        db_domain.cdn_enabled = domain.cdn_enabled

    db.commit()
    db.refresh(db_domain)
    return db_domain

@app.delete("/domains/{domain_id}")
def delete_domain(domain_id: int, db: Session = Depends(get_db)):
    """ حذف دامنه """
    db_domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not db_domain:
        raise HTTPException(status_code=404, detail="دامنه یافت نشد")

    db.delete(db_domain)
    db.commit()
    return {"message": "دامنه با موفقیت حذف شد"}

# روت‌های سابسکریپشن‌ها
@app.post("/subscriptions/", response_model=SubscriptionCreate)
def create_subscription(subscription: SubscriptionCreate, db: Session = Depends(get_db)):
    """ ایجاد سابسکریپشن جدید """
    db_subscription = Subscription(
        uuid=subscription.uuid,
        data_limit=subscription.data_limit,
        expiry_date=subscription.expiry_date,
        max_connections=subscription.max_connections
    )
    db.add(db_subscription)
    db.commit()
    db.refresh(db_subscription)
    return db_subscription

@app.get("/subscriptions/{subscription_id}", response_model=SubscriptionCreate)
def read_subscription(subscription_id: int, db: Session = Depends(get_db)):
    """ دریافت اطلاعات سابسکریپشن """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        raise HTTPException(status_code=404, detail="سابسکریپشن یافت نشد")
    return db_subscription

@app.put("/subscriptions/{subscription_id}", response_model=SubscriptionUpdate)
def update_subscription(subscription_id: int, subscription: SubscriptionUpdate, db: Session = Depends(get_db)):
    """ به‌روزرسانی سابسکریپشن """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        raise HTTPException(status_code=404, detail="سابسکریپشن یافت نشد")

    if subscription.data_limit:
        db_subscription.data_limit = subscription.data_limit
    if subscription.expiry_date:
        db_subscription.expiry_date = subscription.expiry_date
    if subscription.max_connections:
        db_subscription.max_connections = subscription.max_connections

    db.commit()
    db.refresh(db_subscription)
    return db_subscription

@app.delete("/subscriptions/{subscription_id}")
def delete_subscription(subscription_id: int, db: Session = Depends(get_db)):
    """ حذف سابسکریپشن """
    db_subscription = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if not db_subscription:
        raise HTTPException(status_code=404, detail="سابسکریپشن یافت نشد")

    db.delete(db_subscription)
    db.commit()
    return {"message": "سابسکریپشن با موفقیت حذف شد"}

# روت‌های نودها
@app.post("/nodes/", response_model=NodeCreate)
def create_node(node: NodeCreate, db: Session = Depends(get_db)):
    """ ایجاد نود جدید """
    db_node = Node(
        name=node.name,
        ip_address=node.ip_address,
        port=node.port,
        protocol=node.protocol
    )
    db.add(db_node)
    db.commit()
    db.refresh(db_node)
    return db_node

@app.get("/nodes/{node_id}", response_model=NodeCreate)
def read_node(node_id: int, db: Session = Depends(get_db)):
    """ دریافت اطلاعات نود """
    db_node = db.query(Node).filter(Node.id == node_id).first()
    if not db_node:
        raise HTTPException(status_code=404, detail="نود یافت نشد")
    return db_node

@app.put("/nodes/{node_id}", response_model=NodeUpdate)
def update_node(node_id: int, node: NodeUpdate, db: Session = Depends(get_db)):
    """ به‌روزرسانی نود """
    db_node = db.query(Node).filter(Node.id == node_id).first()
    if not db_node:
        raise HTTPException(status_code=404, detail="نود یافت نشد")

    if node.name:
        db_node.name = node.name
    if node.ip_address:
        db_node.ip_address = node.ip_address
    if node.port:
        db_node.port = node.port
    if node.protocol:
        db_node.protocol = node.protocol

    db.commit()
    db.refresh(db_node)
    return db_node

@app.delete("/nodes/{node_id}")
def delete_node(node_id: int, db: Session = Depends(get_db)):
    """ حذف نود """
    db_node = db.query(Node).filter(Node.id == node_id).first()
    if not db_node:
        raise HTTPException(status_code=404, detail="نود یافت نشد")

    db.delete(db_node)
    db.commit()
    return {"message": "نود با موفقیت حذف شد"}

# روت‌های تنظیمات Xray
@app.get("/xray-settings/")
def get_xray_settings():
    """ دریافت تنظیمات Xray """
    return xray_settings

@app.put("/xray-settings/")
def update_xray_settings(settings: XraySettings):
    """ به‌روزرسانی تنظیمات Xray """
    xray_settings.update(settings.dict())
    return {"message": "تنظیمات Xray با موفقیت به‌روزرسانی شد"}

# روت‌های تنظیمات HTTP
@app.get("/http-settings/")
def get_http_settings():
    """ دریافت تنظیمات HTTP """
    return http_settings

@app.put("/http-settings/")
def update_http_settings(settings: HTTPSettings):
    """ به‌روزرسانی تنظیمات HTTP """
    http_settings.update(settings.dict())
    return {"message": "تنظیمات HTTP با موفقیت به‌روزرسانی شد"}

# روت‌های تنظیمات عمومی
@app.get("/language-settings/")
def get_language_settings():
    """ دریافت تنظیمات زبان """
    return language_settings

@app.put("/language-settings/")
def update_language_settings(settings: LanguageSettings):
    """ به‌روزرسانی تنظیمات زبان """
    language_settings.update(settings.dict())
    return {"message": "تنظیمات زبان با موفقیت به‌روزرسانی شد"}

@app.get("/theme-settings/")
def get_theme_settings():
    """ دریافت تنظیمات تم """
    return theme_settings

@app.put("/theme-settings/")
def update_theme_settings(settings: ThemeSettings):
    """ به‌روزرسانی تنظیمات تم """
    theme_settings.update(settings.dict())
    return {"message": "تنظیمات تم با موفقیت به‌روزرسانی شد"}
