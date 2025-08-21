"""
Minimal Cards Gateway JSON decoder for `gatewayjson` content.

This module provides a lightweight version of Cards Gateway JSON decoding
that can work without the full Cards Gateway application dependencies.
"""

import json
import re
from datetime import datetime
from decimal import Decimal
from typing import Any, Dict
from uuid import UUID

from kombu import serialization  # type: ignore

# Minimal implementation for external services
primative_encoding_format = "<<{from_str} {str_repr}>>"


def decode_primative_string(  # pylint: disable=too-many-return-statements
    obj: str,
) -> Any:
    """Decode primative string values without full Cards Gateway dependencies."""
    primative_re = re.compile(
        primative_encoding_format.format(
            from_str=r"(?P<from_str>[^ ]+)",
            str_repr=r"(?P<str_repr>[^>]+)",
        )
    )

    if match := primative_re.fullmatch(obj):
        from_str_path = match.group("from_str")
        str_repr = match.group("str_repr")

        # Handle common types without importing the full Cards Gateway module
        if from_str_path == "builtins:int":
            return int(str_repr)
        if from_str_path == "builtins:float":
            return float(str_repr)
        if from_str_path == "decimal:Decimal":
            return Decimal(str_repr)
        if from_str_path.endswith(":UUID"):
            return UUID(str_repr)
        if "datetime" in from_str_path:
            return datetime.fromisoformat(str_repr)
        # For unknown types, return as string representation
        return f"<{from_str_path}: {str_repr}>"
    return obj


def decode_cards_gateway_json_minimal(  # pylint: disable=too-many-return-statements
    obj: Any,
) -> Any:
    """Minimal Cards Gateway JSON decoder for monitoring purposes."""
    if isinstance(obj, str):
        return decode_primative_string(obj)
    if isinstance(obj, list):
        return [decode_cards_gateway_json_minimal(item) for item in obj]
    if isinstance(obj, dict):
        # Handle special Cards Gateway JSON objects
        if "_model" in obj:
            # For Django models, return a simplified representation
            return {
                "type": "django_model",
                "model": obj.get("_model"),
                "data": {k: v for k, v in obj.items() if not k.startswith("_")},
            }
        if "_type" in obj:
            # For custom objects, return simplified representation
            return {
                "type": "custom_object",
                "class": obj.get("_type"),
                "args": obj.get("args", []),
                "kwargs": obj.get("kwargs", {}),
                "state": obj.get("state", {}),
            }
        if "_import" in obj:
            return {"type": "import", "path": obj["_import"]}
        # Regular dict, recurse
        return {k: decode_cards_gateway_json_minimal(v) for k, v in obj.items()}
    return obj


def loads_minimal(s: str) -> Dict[str, Any]:
    """Load Cards Gateway JSON with minimal decoding for monitoring."""
    return json.loads(s, object_hook=decode_cards_gateway_json_minimal)


def register_minimal_cards_gateway_serializers():
    """Register minimal Cards Gateway serializers for external monitoring tools."""

    serialization.register(
        "gatewayjson",
        json.dumps,  # For encoding, use standard JSON (monitoring tools typically only read)
        loads_minimal,  # Use minimal decoder for reading
        content_type="application/x-gatewayjson",
        content_encoding="utf-8",
    )
