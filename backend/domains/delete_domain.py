from backend.database import get_db
from backend.models import Domain
from sqlalchemy.orm import Session

def delete_domain(db: Session, domain_id: int):
    """ حذف دامنه """
    db_domain = db.query(Domain).filter(Domain.id == domain_id).first()
    if not db_domain:
        return False

    db.delete(db_domain)
    db.commit()
    return True
