from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from typing import List
from sqlalchemy.orm import Session
from .database import get_db
from .schemas import (
    InboundCreate,
    InboundUpdate,
    InboundResponse,
    PortChangeRequest
)
from .services.xray_service import XrayService
from .core.security import get_current_admin

router = APIRouter(
    prefix="/api/v1/xray",
    tags=["Xray Configuration"],
    dependencies=[Depends(get_current_admin)]  # نیاز به احراز هویت ادمین
)

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

@router.delete("/inbounds/{inbound_id}",
               status_code=status.HTTP_204_NO_CONTENT)
async def delete_inbound(
    inbound_id: int,
    db: Session = Depends(get_db)
):
    """حذف اینباند"""
    try:
        service = XrayService(db)
        success = service.delete_inbound(inbound_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="اینباند یافت نشد"
            )
        return JSONResponse(
            status_code=status.HTTP_204_NO_CONTENT,
            content=None
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.patch("/inbounds/{inbound_id}/port")
async def change_port(
    inbound_id: int,
    port_data: PortChangeRequest,
    db: Session = Depends(get_db)
):
    """تغییر پورت اینباند"""
    try:
        service = XrayService(db)
        updated = service.change_inbound_port(
            inbound_id, 
            port_data.new_port
        )
        if not updated:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="اینباند یافت نشد"
            )
        return {
            "status": "success",
            "message": "پورت با موفقیت تغییر یافت"
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.get("/inbounds/{inbound_id}", 
            response_model=InboundResponse)
async def get_inbound(
    inbound_id: int,
    db: Session = Depends(get_db)
):
    """دریافت اطلاعات یک اینباند"""
    try:
        service = XrayService(db)
        inbound = service.get_inbound(inbound_id)
        if not inbound:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="اینباند یافت نشد"
            )
        return {
            "status": "success",
            "data": inbound
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

@router.get("/inbounds", 
            response_model=List[InboundResponse])
async def list_all_inbounds(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """لیست تمام اینباندها"""
    try:
        service = XrayService(db)
        inbounds = service.list_inbounds(skip, limit)
        return {
            "status": "success",
            "data": inbounds,
            "count": len(inbounds)
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
