"""Custom auth: accept any API key (pass-through proxy mode)."""
from litellm.proxy.auth.user_api_key_auth import UserAPIKeyAuth

async def always_allow(request, api_key):
    """Accept any key including empty (transparent proxy: mirror upstream; chat without key fails upstream)."""
    # user_role 必须小写 internal_user（上游 pin 的 LiteLLM 版枚举值，大写 INTERNAL_USER 会被 pydantic 拒收 → 全员 401）
    # 注意：空 key 也放行——上游 models 本就无 key 可读（200），网关保持等价；无 key chat 由上游判 401
    return UserAPIKeyAuth(
        api_key=api_key or "",
        user_role="internal_user",
    )
