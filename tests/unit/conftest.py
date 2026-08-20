import os
from unittest.mock import MagicMock, patch

os.environ.setdefault("LOG_LEVEL_PARAMETER_NAME", "/test/log-level")
os.environ.setdefault("POWERTOOLS_SERVICE_NAME", "checkout_api_test")
os.environ.setdefault("AWS_XRAY_CONTEXT_MISSING", "LOG_ERROR")

_mock_ssm = MagicMock()
_mock_ssm.get_parameter.return_value = {"Parameter": {"Value": "INFO"}}

with patch("boto3.client", return_value=_mock_ssm):
    from src.api import handler  # noqa: F401  (import triggers the cold-start SSM call, mocked above)
