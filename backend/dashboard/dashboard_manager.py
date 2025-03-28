import psutil
from typing import Dict, List
from sqlalchemy.orm import Session
from datetime import datetime
from backend.models import User
from backend.utils import calculate_remaining_days

class DashboardManager:
    def __init__(self, db: Session):
        self.db = db

    # --- آمار سرور ---
    def get_server_stats(self) -> Dict:
        """گرفتن آمار لحظه‌ای سرور"""
        cpu = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage("/")
        net = psutil.net_io_counters()

        return {
            "cpu": {
                "usage": cpu,
                "cores": psutil.cpu_count(logical=False),
                "threads": psutil.cpu_count(logical=True)
            },
            "memory": {
                "total": mem.total,
                "available": mem.available,
                "used": mem.used,
                "percent": mem.percent
            },
            "disk": {
                "total": disk.total,
                "used": disk.used,
                "free": disk.free,
                "percent": disk.percent
            },
            "network": {
                "sent": net.bytes_sent,
                "received": net.bytes_recv
            },
            "uptime": int(psutil.boot_time()),
            "timestamp": int(datetime.now().timestamp())
        }

    # --- آمار ترافیک ---
    def get_traffic_stats(self) -> Dict:
        """محاسبه آمار کلی ترافیک"""
        users = self.db.query(User).all()
        total_limit = sum(u.traffic_limit for u in users)
        total_used = sum(u.traffic_used for u in users)

        return {
            "total": {
                "limit": total_limit,
                "used": total_used,
                "remaining": max(0, total_limit - total_used)
            },
            "average": {
                "usage": (total_used / total_limit * 100) if total_limit > 0 else 0,
                "per_user": (total_used / len(users)) if users else 0
            }
        }

    # --- آمار کاربران ---
    def get_user_stats(self) -> Dict:
        """گرفتن آمار کاربران"""
        users = self.db.query(User).all()
        
        return {
            "counts": {
                "total": len(users),
                "active": len([u for u in users if u.is_active]),
                "online": len([u for u in users if u.is_online]),
                "expired": len([u for u in users if u.expiry_date and u.expiry_date < datetime.now()])
            },
            "traffic": {
                "top_users": sorted(
                    [{"id": u.id, "name": u.name, "used": u.traffic_used} 
                     for u in users],
                    key=lambda x: x["used"],
                    reverse=True
                )[:5]
            }
        }

    # --- گزارش جامع ---
    def get_full_report(self) -> Dict:
        """گزارش کامل تمام آمار"""
        return {
            "server": self.get_server_stats(),
            "traffic": self.get_traffic_stats(),
            "users": self.get_user_stats(),
            "timestamp": int(datetime.now().timestamp())
        }

    # --- لیست کاربران ---
    def get_user_list(self, detailed: bool = False) -> List[Dict]:
        """دریافت لیست کاربران"""
        users = self.db.query(User).all()
        
        if not detailed:
            return [{
                "id": u.id,
                "name": u.name,
                "status": "online" if u.is_online else "offline"
            } for u in users]
        
        return [{
            "id": u.id,
            "name": u.name,
            "uuid": u.uuid,
            "traffic": {
                "limit": u.traffic_limit,
                "used": u.traffic_used,
                "remaining": max(0, u.traffic_limit - u.traffic_used)
            },
            "duration": {
                "total": u.usage_duration,
                "remaining": calculate_remaining_days(u.expiry_date)
            },
            "connections": u.simultaneous_connections,
            "status": {
                "active": u.is_active,
                "online": u.is_online
            },
            "last_activity": u.last_activity.isoformat() if u.last_activity else None
        } for u in users]
