"""Custom auth: accept any API key (pass-through proxy mode)."""
from litellm.proxy.auth.user_api_key_auth import UserAPIKeyAuth

async def always_allow(request, api_key):
    """Always return a valid auth token, regardless of key."""
    return UserAPIKeyAuth(
        api_key=api_key or "",
        user_role="INTERNAL_USER",
    )
