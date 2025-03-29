from fastapi import APIRouter
from .add_domain import router as add_domain_router
from .delete_domain import router as delete_domain_router
from .edit_domain import router as edit_domain_router
from .cdn_management import router as cdn_router
from .domain_config import router as config_router
from .domain_subscription import router as subscription_router

router = APIRouter(
    prefix="/domains",
    tags=["Domains Management"],
    responses={
        404: {"description": "Domain not found"},
        403: {"description": "Operation not permitted"}
    }
)

# Include all sub-routers
router.include_router(add_domain_router)
router.include_router(delete_domain_router)
router.include_router(edit_domain_router)
router.include_router(cdn_router)
router.include_router(config_router)
router.include_router(subscription_router)

__all__ = [
    "router",
    "add_domain_router",
    "delete_domain_router",
    "edit_domain_router",
    "cdn_router",
    "config_router",
    "subscription_router"
]
