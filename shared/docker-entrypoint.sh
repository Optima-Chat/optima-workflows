#!/bin/bash
# ==============================================================================
# Universal Docker Entrypoint for ECS Deployment
# 使用 Infisical CLI 获取 secrets 并注入环境变量
# 支持 EFS 缓存 fallback（当 Infisical 不可用时）
#
# 来源: https://github.com/Optima-Chat/optima-workflows/blob/main/shared/docker-entrypoint.sh
# 版本: 2.0.0
#
# 使用场景：
# - ECS 部署：设置 USE_INFISICAL_CLI=true，脚本从 Infisical 获取 secrets
# - EC2/本地：不设置这个变量，直接执行命令（secrets 由外部注入）
#
# 必需环境变量（ECS 模式）：
# - INFISICAL_CLIENT_ID      Machine Identity Client ID
# - INFISICAL_CLIENT_SECRET  Machine Identity Client Secret
# - INFISICAL_PROJECT_ID     Infisical 项目 ID
# - INFISICAL_PATH           密钥路径，如 /services/user-auth
# - SERVICE_NAME             服务名称，用于 EFS 缓存隔离
#
# 可选环境变量：
# - INFISICAL_ENVIRONMENT    环境名称，默认 staging
# - INFISICAL_DOMAIN         Infisical 域名，默认 https://secrets.optima.onl
#
# EFS 缓存：
# - 挂载路径: /mnt/secrets-cache
# - 缓存文件: /mnt/secrets-cache/{SERVICE_NAME}/.env.cache
# - 每次成功获取后更新缓存
# - Infisical 不可用时使用缓存启动
# ==============================================================================

set -e

# ==============================================================================
# EFS 缓存函数
# ==============================================================================

SERVICE_NAME="${SERVICE_NAME:-unknown}"
CACHE_DIR="/mnt/secrets-cache/${SERVICE_NAME}"
CACHE_FILE="${CACHE_DIR}/.env.cache"

# 更新缓存
update_cache() {
    # 检查 EFS 是否挂载
    if [ ! -d "/mnt/secrets-cache" ]; then
        echo "⚠️  Warning: /mnt/secrets-cache not mounted, skipping cache update"
        return 1
    fi

    mkdir -p "$CACHE_DIR" && chmod 700 "$CACHE_DIR"

    infisical export \
        --projectId="$INFISICAL_PROJECT_ID" \
        --env="$INFISICAL_ENVIRONMENT" \
        --path="$INFISICAL_PATH" \
        --recursive \
        --format=dotenv > "$CACHE_FILE"

    chmod 600 "$CACHE_FILE"
    echo "✅ Cache updated (EFS: $CACHE_FILE)"
}

# 从缓存加载
load_from_cache() {
    echo "⚠️  WARNING: Using cached secrets from EFS"
    echo "    Cache file: $CACHE_FILE"
    set -a
    source "$CACHE_FILE"
    set +a
}

# ==============================================================================
# 主逻辑
# ==============================================================================

if [ "$USE_INFISICAL_CLI" = "true" ]; then
    echo "=== ECS Mode: Infisical with EFS Cache Fallback ==="
    echo "  Service: $SERVICE_NAME"

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

    if [ -z "$INFISICAL_PATH" ]; then
        echo "ERROR: INFISICAL_PATH is required (e.g., /services/user-auth)"
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

    # 尝试从 Infisical 获取 secrets
    echo "🔐 Attempting Infisical login..."
    INFISICAL_TOKEN=$(infisical login \
        --method=universal-auth \
        --client-id="$INFISICAL_CLIENT_ID" \
        --client-secret="$INFISICAL_CLIENT_SECRET" \
        --silent \
        --plain 2>/dev/null || echo "")

    if [ -n "$INFISICAL_TOKEN" ]; then
        # Infisical 可用
        echo "✅ Infisical connected"
        export INFISICAL_TOKEN

        # 更新 EFS 缓存（失败不影响启动）
        update_cache || echo "⚠️  Cache update failed (continuing anyway)"

        # 使用 infisical run 启动应用
        exec infisical run \
            --projectId="$INFISICAL_PROJECT_ID" \
            --env="$INFISICAL_ENVIRONMENT" \
            --path="$INFISICAL_PATH" \
            --recursive \
            -- "$@"
    else
        # Infisical 不可用，尝试使用缓存
        echo "❌ Infisical unavailable, checking EFS cache..."

        if [ -f "$CACHE_FILE" ]; then
            load_from_cache
            exec "$@"
        else
            echo "❌ ERROR: No cache available in EFS"
            echo "   Cache path: $CACHE_FILE"
            echo "   First deployment requires Infisical to be available"
            exit 1
        fi
    fi
else
    # EC2/本地模式：直接执行命令（环境变量由外部注入）
    exec "$@"
fi
