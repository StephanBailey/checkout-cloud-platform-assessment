import base64
import binascii
import json
import os
from datetime import datetime, timezone
from http import HTTPStatus
from pathlib import Path
from typing import Any

import boto3
from aws_lambda_powertools import Logger, Tracer
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.utilities.validation import SchemaValidationError, validate

logger = Logger()
tracer = Tracer()

_ssm_client = boto3.client("ssm")
_schema = json.loads((Path(__file__).parent / "request_schema.json").read_text())


def _current_log_level(default: str = "INFO") -> str:
    parameter_name = os.environ["LOG_LEVEL_PARAMETER_NAME"]
    try:
        return _ssm_client.get_parameter(Name=parameter_name)["Parameter"]["Value"]
    except Exception:
        logger.warning("Failed to fetch log level from SSM, falling back to default", extra={"default": default})
        return default


logger.setLevel(_current_log_level())


def _response(status_code: HTTPStatus, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code.value,
        "statusDescription": f"{status_code.value} {status_code.phrase}",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _parse_body(event: dict[str, Any]) -> dict[str, Any]:
    raw_body = event.get("body", "{}")
    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(raw_body).decode("utf-8")
    return json.loads(raw_body)


@logger.inject_lambda_context()
@tracer.capture_lambda_handler
def lambda_handler(event: dict[str, Any], context: LambdaContext) -> dict[str, Any]:
    if event.get("httpMethod") != "POST":
        # ALB target group health checks land here.
        return _response(HTTPStatus.OK, {"status": "ok"})

    try:
        body = _parse_body(event)
    except (json.JSONDecodeError, UnicodeDecodeError, binascii.Error):
        logger.warning("Request body is not valid JSON")
        return _response(HTTPStatus.BAD_REQUEST, {"error": "Request body must be valid JSON"})

    try:
        validate(event=body, schema=_schema)
    except SchemaValidationError as exc:
        logger.warning("Request failed schema validation", extra={"error": str(exc)})
        return _response(HTTPStatus.BAD_REQUEST, {"error": "Invalid request", "details": str(exc)})

    try:
        logger.info("Processing checkout message")

        return _response(
            HTTPStatus.OK,
            {
                "message": body["message"],
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "requestId": context.aws_request_id,
            },
        )
    except Exception:
        logger.exception("Unhandled error processing request")
        return _response(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "Internal server error"})
