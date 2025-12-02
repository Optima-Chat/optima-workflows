#!/bin/bash
# ==============================================================================
# Universal Docker Entrypoint for ECS Deployment
# 使用 Infisical CLI 获取 secrets 并注入环境变量
#
# 来源: https://github.com/Optima-Chat/optima-workflows/blob/main/shared/docker-entrypoint.sh
# 版本: 1.0.0
#
# 使用场景：
# - ECS 部署：设置 USE_INFISICAL_CLI=true，脚本从 Infisical 获取 secrets
# - EC2/本地：不设置这个变量，直接执行命令（secrets 由外部注入）
#
# 必需环境变量（ECS 模式）：
# - INFISICAL_CLIENT_ID      Machine Identity Client ID
# - INFISICAL_CLIENT_SECRET  Machine Identity Client Secret
# - INFISICAL_PROJECT_ID     Infisical 项目 ID
# - INFISICAL_PATH           密钥路径，如 /mcp-tools/comfy-mcp
#
# 可选环境变量：
# - INFISICAL_ENVIRONMENT    环境名称，默认 staging
# - INFISICAL_DOMAIN         Infisical 域名，默认 https://secrets.optima.onl
# ==============================================================================

set -e

# 检查是否需要从 Infisical 获取 secrets
if [ "$USE_INFISICAL_CLI" = "true" ]; then
    echo "=== ECS Mode: Loading secrets from Infisical ==="

    # 设置 Infisical 域名（默认使用自建服务）
    INFISICAL_DOMAIN="${INFISICAL_DOMAIN:-https://secrets.optima.onl}"

    # 验证必要的环境变量
    if [ -z "$INFISICAL_CLIENT_ID" ] || [ -z "$INFISICAL_CLIENT_SECRET" ]; then
        echo "ERROR: INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET are required"
        exit 1
    fi

    if [ -z "$INFISICAL_PROJECT_ID" ]; then
        echo "ERROR: INFISICAL_PROJECT_ID is not set"
        exit 1
    fi

    # INFISICAL_PATH 必须由各服务指定，不再有默认值
    if [ -z "$INFISICAL_PATH" ]; then
        echo "ERROR: INFISICAL_PATH is required (e.g., /mcp-tools/comfy-mcp)"
        exit 1
    fi

    # 设置默认环境
    INFISICAL_ENVIRONMENT="${INFISICAL_ENVIRONMENT:-staging}"

    echo "  Domain: $INFISICAL_DOMAIN"
    echo "  Project: $INFISICAL_PROJECT_ID"
    echo "  Environment: $INFISICAL_ENVIRONMENT"
    echo "  Path: $INFISICAL_PATH"
    echo "  Command: $@"
    echo "=============================================="

    # 设置 Infisical API URL（用于 self-hosted 实例）
    export INFISICAL_API_URL="$INFISICAL_DOMAIN"

    # 步骤 1: 使用 Universal Auth 登录获取 token
    echo "🔐 Logging in to Infisical..."
    export INFISICAL_TOKEN=$(infisical login \
        --method=universal-auth \
        --client-id="$INFISICAL_CLIENT_ID" \
        --client-secret="$INFISICAL_CLIENT_SECRET" \
        --silent \
        --plain)

    if [ -z "$INFISICAL_TOKEN" ]; then
        echo "❌ ERROR: Failed to obtain Infisical token"
        exit 1
    fi

    echo "✅ Successfully authenticated with Infisical"

    # 步骤 2: 使用 token 执行命令并注入环境变量
    exec infisical run \
        --projectId="$INFISICAL_PROJECT_ID" \
        --env="$INFISICAL_ENVIRONMENT" \
        --path="$INFISICAL_PATH" \
        --recursive \
        -- "$@"
else
    # EC2/本地模式：直接执行命令（环境变量由外部注入）
    exec "$@"
fi
