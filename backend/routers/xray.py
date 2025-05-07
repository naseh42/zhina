from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from backend.database import get_db

from xray_config.inbounds import (
    create_inbound, get_inbounds, update_inbound, delete_inbound
)
from xray_config.tls import (
    create_tls, get_tls_config, update_tls, delete_tls
)
from xray_config.subscription import (
    create_subscription, get_subscriptions, update_subscription, delete_subscription
)
from xray_config.protocols import (
    get_protocols, update_protocol
)
from xray_config.setting import (
    get_xray_settings, update_xray_settings
)
from xray_config.xray_manager import (
    restart_xray, reload_xray, get_xray_status
)

router = APIRouter(prefix="/xray", tags=["Xray"])

# ---------------- Inbounds ----------------
router.post("/inbounds")(create_inbound)
router.get("/inbounds")(get_inbounds)
router.put("/inbounds/{inbound_id}")(update_inbound)
router.delete("/inbounds/{inbound_id}")(delete_inbound)

# ---------------- TLS ----------------
router.post("/tls")(create_tls)
router.get("/tls")(get_tls_config)
router.put("/tls")(update_tls)
router.delete("/tls")(delete_tls)

# ---------------- Subscriptions ----------------
router.post("/subscriptions")(create_subscription)
router.get("/subscriptions")(get_subscriptions)
router.put("/subscriptions/{subscription_id}")(update_subscription)
router.delete("/subscriptions/{subscription_id}")(delete_subscription)

# ---------------- Protocols ----------------
router.get("/protocols")(get_protocols)
router.put("/protocols")(update_protocol)

# ---------------- Settings ----------------
router.get("/settings")(get_xray_settings)
router.put("/settings")(update_xray_settings)

# ---------------- Manager ----------------
router.post("/restart")(restart_xray)
router.post("/reload")(reload_xray)
router.get("/status")(get_xray_status)
