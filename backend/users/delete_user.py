from backend.database import get_db
from backend.models import User
from sqlalchemy.orm import Session

def delete_user(db: Session, user_id: int):
    """ حذف کاربر """
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        return False

    db.delete(db_user)
    db.commit()
    return True
