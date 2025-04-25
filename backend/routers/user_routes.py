from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from backend.database import get_db
from backend.schemas import UserCreate, UserUpdate, UserResponse
from backend.user.user_manager import UserManager
from typing import List
from backend.models import User

router = APIRouter(prefix="/users", tags=["Users"])

@router.post("/", response_model=UserResponse)
def create_user(user_data: UserCreate, db: Session = Depends(get_db)):
    manager = UserManager(db)
    user = manager.create(user_data)
    return user

@router.put("/{user_id}", response_model=UserResponse)
def update_user(user_id: int, user_data: UserUpdate, db: Session = Depends(get_db)):
    manager = UserManager(db)
    updated_user = manager.update(user_id, user_data)
    if not updated_user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    return updated_user

@router.delete("/{user_id}", status_code=204)
def delete_user(user_id: int, db: Session = Depends(get_db)):
    manager = UserManager(db)
    success = manager.delete(user_id)
    if not success:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    return

@router.get("/", response_model=List[UserResponse])
def list_users(db: Session = Depends(get_db)):
    users = db.query(User).all()
    return users

@router.get("/{user_id}", response_model=UserResponse)
def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="کاربر یافت نشد")
    return user
