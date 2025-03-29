from fastapi import APIRouter
from .dashboard_manager import router as manager_router
from .server_stats import router as server_stats_router
from .traffic_stats import router as traffic_stats_router
from .user_stats import router as user_stats_router

router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard Analytics"],
    responses={
        404: {"description": "Resource not found"},
        500: {"description": "Internal server error"}
    }
)

# Include all dashboard sub-routers
router.include_router(manager_router)
router.include_router(server_stats_router)
router.include_router(traffic_stats_router)
router.include_router(user_stats_router)

__all__ = [
    "router",
    "manager_router",
    "server_stats_router",
    "traffic_stats_router",
    "user_stats_router"
]
