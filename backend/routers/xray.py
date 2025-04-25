from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from typing import List
from sqlalchemy.orm import Session
from .database import get_db
from .schemas import (
    InboundCreate,
    InboundUpdate,
    InboundResponse,
    PortChangeRequest,
    ProxyCreate,  # اضافه کردن پروکسی
    ProxyUpdate,  # اضافه کردن پروکسی
    DomainCreate,  # اضافه کردن دامنه
    DomainUpdate,  # اضافه کردن دامنه
    TLSConfigCreate,  # اضافه کردن تنظیمات TLS
    SubscriptionCreate,  # اضافه کردن سابسکریپشن
)
from .services.xray_service import XrayService
from .core.security import get_current_admin

router = APIRouter(
    prefix="/api/v1/xray",
    tags=["Xray Configuration"],
    dependencies=[Depends(get_current_admin)]  # نیاز به احراز هویت ادمین
)

# مسیرهای موجود برای اینباندها

@router.post("/inbounds", 
             response_model=InboundResponse,
             status_code=status.HTTP_201_CREATED)
async def create_inbound(
    inbound: InboundCreate, 
    db: Session = Depends(get_db)
):
    """ایجاد اینباند جدید"""
    try:
        service = XrayService(db)
        new_inbound = service.add_inbound(inbound)
        return {
            "status": "success",
            "data": new_inbound,
            "message": "اینباند با موفقیت ایجاد شد"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.put("/inbounds/{inbound_id}", 
            response_model=InboundResponse)
async def update_inbound(
    inbound_id: int,
    inbound: InboundUpdate,
    db: Session = Depends(get_db)
):
    """به‌روزرسانی اینباند"""
    try:
        service = XrayService(db)
        updated_inbound = service.update_inbound(inbound_id, inbound)
        if not updated_inbound:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="اینباند یافت نشد"
            )
        return {
            "status": "success",
            "data": updated_inbound
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

# مسیرهای جدید برای پروکسی‌ها و دامنه‌ها

@router.post("/proxies", 
             response_model=ProxyCreate, 
             status_code=status.HTTP_201_CREATED)
async def create_proxy(
    proxy: ProxyCreate, 
    db: Session = Depends(get_db)
):
    """ایجاد پروکسی جدید"""
    try:
        service = XrayService(db)
        new_proxy = service.add_proxy(proxy)
        return {
            "status": "success",
            "data": new_proxy,
            "message": "پروکسی با موفقیت ایجاد شد"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.post("/domains", 
             response_model=DomainCreate, 
             status_code=status.HTTP_201_CREATED)
async def create_domain(
    domain: DomainCreate, 
    db: Session = Depends(get_db)
):
    """ایجاد دامنه جدید"""
    try:
        service = XrayService(db)
        new_domain = service.add_domain(domain)
        return {
            "status": "success",
            "data": new_domain,
            "message": "دامنه با موفقیت ایجاد شد"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

# مسیرهای جدید برای TLS

@router.post("/tls", 
             response_model=TLSConfigCreate, 
             status_code=status.HTTP_201_CREATED)
async def create_tls(
    tls_config: TLSConfigCreate, 
    db: Session = Depends(get_db)
):
    """ایجاد تنظیمات TLS"""
    try:
        service = XrayService(db)
        new_tls = service.add_tls_config(tls_config)
        return {
            "status": "success",
            "data": new_tls,
            "message": "تنظیمات TLS با موفقیت ایجاد شد"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

# مسیرهای جدید برای سابسکریپشن‌ها

@router.post("/subscriptions", 
             response_model=SubscriptionCreate, 
             status_code=status.HTTP_201_CREATED)
async def create_subscription(
    subscription: SubscriptionCreate, 
    db: Session = Depends(get_db)
):
    """ایجاد سابسکریپشن جدید"""
    try:
        service = XrayService(db)
        new_subscription = service.add_subscription(subscription)
        return {
            "status": "success",
            "data": new_subscription,
            "message": "سابسکریپشن با موفقیت ایجاد شد"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
