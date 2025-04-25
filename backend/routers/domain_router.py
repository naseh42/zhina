from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.models import Domain
from backend.schemas import DomainCreate, DomainResponse
from backend.domains.domain_manager import DomainManager

router = APIRouter()

@router.post("/", response_model=DomainResponse)
async def add_domain(
    domain_data: DomainCreate,
    db: Session = Depends(get_db)
):
    """افزودن دامنه جدید"""
    try:
        manager = DomainManager(db)
        return manager.create(domain_data)
    except Exception as e:
        raise HTTPException(status_code=400, detail="Failed to add domain")

@router.get("/", response_model=List[DomainResponse])
async def get_domains(db: Session = Depends(get_db)):
    """دریافت لیست دامنه‌ها"""
    try:
        domains = db.query(Domain).all()
        return domains
    except Exception as e:
        raise HTTPException(status_code=400, detail="Failed to retrieve domains")

@router.delete("/{domain_id}", status_code=204)
async def delete_domain(domain_id: int, db: Session = Depends(get_db)):
    """حذف دامنه"""
    try:
        manager = DomainManager(db)
        manager.delete(domain_id)
        return {"message": "Domain deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=400, detail="Failed to delete domain")

@router.put("/{domain_id}", response_model=DomainResponse)
async def update_domain(
    domain_id: int,
    domain_data: DomainCreate,
    db: Session = Depends(get_db)
):
    """ویرایش دامنه"""
    try:
        manager = DomainManager(db)
        return manager.update(domain_id, domain_data)
    except Exception as e:
        raise HTTPException(status_code=400, detail="Failed to update domain")
