# Optima Workflows

Optima 服务的共享 GitHub Actions Reusable Workflows。

## 可用的 Workflows

### `_deploy-ecs.yml` - ECS 部署

通用的 ECS 部署 workflow，支持：
- Stage / Prod / Both 环境部署
- 可选的测试运行
- 可选的数据库迁移
- 多镜像构建（规划中）
- 健康检查
- 并发控制

## 使用方法

### 简单 MCP 工具（如 comfy-mcp）

```yaml
name: Deploy

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [stage, prod, both]
        default: 'stage'
      skip_build:
        type: boolean
        default: false

jobs:
  deploy:
    uses: Optima-Chat/optima-workflows/.github/workflows/_deploy-ecs.yml@main
    with:
      service_name: comfy-mcp
      environment: ${{ github.event_name == 'push' && 'prod' || inputs.environment }}
      skip_build: ${{ inputs.skip_build || false }}
    secrets: inherit
```

### 有迁移的服务（如 google-ads-mcp）

```yaml
name: Deploy

on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [stage, prod, both]
        default: 'stage'
      skip_migration:
        type: boolean
        default: false

jobs:
  deploy:
    uses: Optima-Chat/optima-workflows/.github/workflows/_deploy-ecs.yml@main
    with:
      service_name: ads-mcp
      environment: ${{ github.event_name == 'push' && 'prod' || inputs.environment }}
      has_migration: true
      skip_migration: ${{ inputs.skip_migration || false }}
    secrets: inherit
```

### Core Service（如 user-auth）

```yaml
name: Deploy

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [stage, prod]
        default: 'stage'
      skip_tests:
        type: boolean
        default: false

jobs:
  deploy:
    uses: Optima-Chat/optima-workflows/.github/workflows/_deploy-ecs.yml@main
    with:
      service_name: user-auth
      environment: ${{ github.ref_type == 'tag' && 'prod' || github.event_name == 'pull_request' && 'none' || inputs.environment || 'stage' }}
      has_tests: true
      skip_tests: ${{ inputs.skip_tests || github.ref_type == 'tag' }}
      has_migration: true
    secrets: inherit
```

## 输入参数

| 参数 | 必填 | 默认值 | 说明 |
|------|-----|-------|------|
| `service_name` | ✅ | - | 服务名称（如 user-auth, comfy-mcp） |
| `environment` | ✅ | - | 部署环境：stage / prod / both |
| `skip_build` | ❌ | false | 跳过构建，使用 latest 镜像 |
| `image_tag` | ❌ | 自动生成 | 指定镜像 tag |
| `has_tests` | ❌ | false | 是否运行测试 |
| `skip_tests` | ❌ | false | 本次跳过测试 |
| `has_migration` | ❌ | false | 是否需要数据库迁移 |
| `skip_migration` | ❌ | false | 本次跳过迁移 |
| `health_check_path` | ❌ | /health | 健康检查路径 |
| `stage_domain` | ❌ | 自动推断 | Stage 环境域名 |
| `prod_domain` | ❌ | 自动推断 | Prod 环境域名 |

## 域名推断规则

如果不指定 `stage_domain` / `prod_domain`，会自动推断：

| 服务名 | Stage 域名 | Prod 域名 |
|-------|-----------|----------|
| `comfy-mcp` | comfy.mcp.stage.optima.onl | comfy.mcp.optima.onl |
| `user-auth` | user-auth.stage.optima.onl | user-auth.optima.onl |

## 触发策略建议

| 触发方式 | 测试 | Stage | Prod | 说明 |
|---------|-----|-------|------|------|
| `push: main` | ✅ | ✅ | ❌ | 日常开发 |
| `pull_request` | ✅ | ❌ | ❌ | PR 检查 |
| `push: tags/v*` | ❌ | ❌ | ✅ | 发版 |
| `workflow_dispatch` | 可选 | 可选 | 可选 | 手动控制 |

## 共享资源

### `shared/docker-entrypoint.sh` - 通用 Entrypoint

所有 ECS 服务使用的统一 Docker Entrypoint 脚本，用于从 Infisical 获取密钥。

**使用方法**：

1. 直接复制到你的项目：
```bash
curl -o docker-entrypoint.sh https://raw.githubusercontent.com/Optima-Chat/optima-workflows/main/shared/docker-entrypoint.sh
chmod +x docker-entrypoint.sh
```

2. 在 Dockerfile 中使用：
```dockerfile
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["python", "main.py"]
```

3. 在 ECS Task Definition 中设置环境变量：
```json
{
  "environment": [
    {"name": "USE_INFISICAL_CLI", "value": "true"},
    {"name": "INFISICAL_PATH", "value": "/mcp-tools/comfy-mcp"}
  ]
}
```

**必需环境变量**（ECS 模式）：

| 变量 | 说明 | 示例 |
|------|------|------|
| `USE_INFISICAL_CLI` | 启用 Infisical 模式 | `true` |
| `INFISICAL_CLIENT_ID` | Machine Identity ID | 从 SSM 获取 |
| `INFISICAL_CLIENT_SECRET` | Machine Identity Secret | 从 SSM 获取 |
| `INFISICAL_PROJECT_ID` | 项目 ID | 从 SSM 获取 |
| `INFISICAL_PATH` | 密钥路径 | `/mcp-tools/comfy-mcp` |

**可选环境变量**：

| 变量 | 默认值 | 说明 |
|------|-------|------|
| `INFISICAL_ENVIRONMENT` | `staging` | 环境名称 |
| `INFISICAL_DOMAIN` | `https://secrets.optima.onl` | Infisical 域名 |

## 版本

建议锁定到特定 tag 而不是 `@main`：

```yaml
uses: Optima-Chat/optima-workflows/.github/workflows/_deploy-ecs.yml@v1.0.0
```
