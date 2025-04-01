from fastapi import APIRouter
import psutil
from typing import Dict

router = APIRouter()  # این خط را اضافه کنید

def get_server_stats() -> Dict:
    """ دریافت آمار سرور """
    cpu_usage = psutil.cpu_percent(interval=1)
    memory_info = psutil.virtual_memory()
    disk_usage = psutil.disk_usage("/")
    network_io = psutil.net_io_counters()

    stats = {
        "cpu_usage": cpu_usage,
        "memory_usage": {
            "total": memory_info.total,
            "available": memory_info.available,
            "used": memory_info.used,
            "percent": memory_info.percent
        },
        "disk_usage": {
            "total": disk_usage.total,
            "used": disk_usage.used,
            "free": disk_usage.free,
            "percent": disk_usage.percent
        },
        "network_io": {
            "bytes_sent": network_io.bytes_sent,
            "bytes_recv": network_io.bytes_recv
        }
    }
    return stats

# اضافه کردن route برای دریافت آمار سرور
@router.get("/stats", response_model=Dict)
async def fetch_server_stats():
    return get_server_stats()
