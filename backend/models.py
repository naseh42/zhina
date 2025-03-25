from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship
from backend.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    uuid = Column(String, unique=True, index=True)
    traffic_limit = Column(Integer, default=0)
    usage_duration = Column(Integer, default=0)
    simultaneous_connections = Column(Integer, default=1)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime)
    updated_at = Column(DateTime)

    domains = relationship("Domain", back_populates="owner")

class Domain(Base):
    __tablename__ = "domains"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    description = Column(JSON, nullable=True)
    owner_id = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime)
    updated_at = Column(DateTime)

    owner = relationship("User", back_populates="domains")

class Subscription(Base):
    __tablename__ = "subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    uuid = Column(String, unique=True, index=True)
    data_limit = Column(Integer, default=0)
    expiry_date = Column(DateTime)
    max_connections = Column(Integer, default=1)
    user_id = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime)
    updated_at = Column(DateTime)

class Setting(Base):
    __tablename__ = "settings"

    id = Column(Integer, primary_key=True, index=True)
    language = Column(String, default="fa")
    theme = Column(String, default="dark")
    enable_notifications = Column(Boolean, default=True)
    preferences = Column(JSON, nullable=True)
    created_at = Column(DateTime)
    updated_at = Column(DateTime)

class Node(Base):
    __tablename__ = "nodes"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    ip_address = Column(String)
    port = Column(Integer)
    protocol = Column(String)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime)
    updated_at = Column(DateTime)

class Inbound(Base):
    __tablename__ = "inbounds"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    settings = Column(JSON, nullable=True)
    created_at = Column(DateTime)
    updated_at = Column(DateTime)
