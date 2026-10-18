"""Custom callback: pass client API key to upstream (transparent proxy).

- async_pre_call_hook: stash client key into data["metadata"]
- async_pre_call_deployment_hook: override kwargs["api_key"] with client key
"""
from litellm.integrations.custom_logger import CustomLogger
from litellm._logging import verbose_proxy_logger


class PassthroughKeyCallback(CustomLogger):
    async def async_pre_call_hook(
        self, user_api_key_dict, cache, data, call_type,
    ):
        try:
            client_key = getattr(user_api_key_dict, "api_key", None)
            if client_key:
                data.setdefault("metadata", {})
                data["metadata"]["_passthrough_client_key"] = client_key
        except Exception as e:
            verbose_proxy_logger.debug("passthrough pre_call_hook error: %s", e)
        return data

    async def async_pre_call_deployment_hook(self, kwargs, call_type):
        try:
            client_key = (kwargs.get("metadata") or {}).get("_passthrough_client_key")
            if client_key:
                kwargs["api_key"] = client_key
        except Exception as e:
            verbose_proxy_logger.debug("passthrough deployment_hook error: %s", e)
        return kwargs


passthrough_callback = PassthroughKeyCallback()
