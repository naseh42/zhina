from fastapi import APIRouter, Depends, HTTPException
from backend.xray_config import (
    add_inbound, update_inbound, delete_inbound,
    change_inbound_port, get_inbound, list_inbounds
)
from backend.schemas import InboundConfig, InboundResponse

router = APIRouter(prefix="/xray", tags=["Xray"])

@router.post("/inbounds", response_model=InboundResponse)
def create_inbound(inbound: InboundConfig):
    add_inbound(inbound)
    return {"message": "Inbound created successfully"}

@router.put("/inbounds/{port}", response_model=InboundResponse)
def modify_inbound(port: int, inbound: InboundConfig):
    update_inbound(port, inbound)
    return {"message": "Inbound updated successfully"}

@router.delete("/inbounds/{port}")
def remove_inbound(port: int):
    delete_inbound(port)
    return {"message": "Inbound deleted successfully"}

@router.patch("/inbounds/{old_port}/change-port")
def modify_inbound_port(old_port: int, new_port: int):
    change_inbound_port(old_port, new_port)
    return {"message": "Inbound port changed successfully"}

@router.get("/inbounds/{port}", response_model=InboundResponse)
def fetch_inbound(port: int):
    return get_inbound(port)

@router.get("/inbounds", response_model=List[InboundResponse])
def fetch_all_inbounds():
    return list_inbounds()
