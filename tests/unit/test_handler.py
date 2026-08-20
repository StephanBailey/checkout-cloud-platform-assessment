import base64
import json
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from src.api import handler


def _context(request_id: str = "test-request-id") -> SimpleNamespace:
    return SimpleNamespace(
        aws_request_id=request_id,
        function_name="checkout_api-test",
        memory_limit_in_mb=128,
        invoked_function_arn="arn:aws:lambda:eu-west-1:123456789012:function:checkout_api-test",
        function_version="$LATEST",
        get_remaining_time_in_millis=lambda: 30000,
    )


def _post_event(body: dict) -> dict:
    return {"httpMethod": "POST", "body": json.dumps(body)}


class TestHealthCheck:
    def test_non_post_returns_ok(self):
        response = handler.lambda_handler({"httpMethod": "GET"}, _context())

        assert response["statusCode"] == 200
        assert json.loads(response["body"]) == {"status": "ok"}

    def test_missing_http_method_treated_as_health_check(self):
        response = handler.lambda_handler({}, _context())

        assert response["statusCode"] == 200


class TestSuccessfulRequest:
    def test_echoes_message_timestamp_and_request_id(self):
        event = _post_event({"message": "hello"})

        response = handler.lambda_handler(event, _context("abc-123"))

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["message"] == "hello"
        assert body["requestId"] == "abc-123"
        assert "timestamp" in body

    def test_handles_base64_encoded_body(self):
        raw = json.dumps({"message": "encoded"}).encode("utf-8")
        event = {
            "httpMethod": "POST",
            "body": base64.b64encode(raw).decode("utf-8"),
            "isBase64Encoded": True,
        }

        response = handler.lambda_handler(event, _context())

        assert response["statusCode"] == 200
        assert json.loads(response["body"])["message"] == "encoded"


class TestValidationErrors:
    def test_missing_message_field_returns_400(self):
        response = handler.lambda_handler(_post_event({}), _context())

        assert response["statusCode"] == 400
        assert "error" in json.loads(response["body"])

    def test_empty_message_returns_400(self):
        response = handler.lambda_handler(_post_event({"message": ""}), _context())

        assert response["statusCode"] == 400

    def test_unexpected_field_rejected(self):
        response = handler.lambda_handler(_post_event({"message": "hi", "extra": "nope"}), _context())

        assert response["statusCode"] == 400

    def test_invalid_json_body_returns_400(self):
        event = {"httpMethod": "POST", "body": "not json"}

        response = handler.lambda_handler(event, _context())

        assert response["statusCode"] == 400


class TestLogLevelFallback:
    def test_falls_back_to_default_on_ssm_failure(self):
        from botocore.exceptions import ClientError

        mock_client = MagicMock()
        mock_client.get_parameter.side_effect = ClientError(
            {"Error": {"Code": "ParameterNotFound", "Message": "not found"}}, "GetParameter"
        )

        with patch.object(handler, "_ssm_client", mock_client):
            assert handler._current_log_level() == "INFO"
