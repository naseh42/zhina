from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from backend.database import get_db
from backend import schemas, models
from backend.utils import get_current_user

router = APIRouter(prefix="/api/domains", tags=["Domains"])

@router.delete("/{domain_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_domain(
    domain_id: int,
    db: Session = Depends(get_db),
    current_user: schemas.User = Depends(get_current_user)
):
    """
    حذف دامنه با شناسه مشخص
    - نیاز به احراز هویت دارد
    - فقط مالک دامنه یا ادمین می‌تواند حذف کند
    """
    db_domain = db.query(models.Domain).filter(models.Domain.id == domain_id).first()
    
    if not db_domain:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="دامنه مورد نظر یافت نشد"
        )
    
    if db_domain.owner_id != current_user.id and not current_user.is_superuser:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="شما مجوز حذف این دامنه را ندارید"
        )
    
    db.delete(db_domain)
    db.commit()
    
    return {"message": "دامنه با موفقیت حذف شد"}
