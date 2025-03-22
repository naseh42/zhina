from pydantic import BaseModel
from typing import Dict, Optional

class TLSSettings(BaseModel):
    enable_tls: bool = True
    tls_certificate: Optional[str] = None
    tls_key: Optional[str] = None
    tls_settings: Dict = {
        "serverName": "example.com",
        "alpn": ["h2", "http/1.1"],
        "minVersion": "1.2",
        "maxVersion": "1.3"
    }

    def set_tls_certificate(self, cert_path: str, key_path: str):
        """ تنظیم مسیر گواهی TLS """
        self.tls_certificate = cert_path
        self.tls_key = key_path

class HTTPSettings(BaseModel):
    enable_http: bool = True
    http_settings: Dict = {
        "timeout": 300,
        "allowTransparent": False
    }

tls_settings = TLSSettings()
http_settings = HTTPSettings()
