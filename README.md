# grpc-lb-test

测试 gRPC 在 Kubernetes 下的负载均衡情况。

本项目使用自定义的 Go gRPC server 和 client，在响应中返回 Pod 的 hostname、Pod 名称和 IP，方便观察负载分布。

## 前置依赖

1. kind: `brew install kind`
2. grpcurl: `brew install grpcurl`
3. protoc 28.3

## 项目结构

```
grpc-lb-test/
├── proto/                      # protobuf 定义
│   └── echo.proto             # Echo 服务的 proto 定义
├── protogen/                   # proto 生成的 Go 代码
│   └── echo/                  # 由 protoc 自动生成，client 和 server 共同依赖
│       ├── echo.pb.go
│       └── echo_grpc.pb.go
├── server/                     # gRPC server
│   ├── main.go                # 最小 Echo server 实现
│   ├── Dockerfile             # Server 镜像构建文件
│   └── bin/                   # 编译输出目录（linux 二进制）
├── client/                     # gRPC 压测 client
│   ├── main.go                # 支持多连接、并发、统计分布
│   ├── Dockerfile             # Client 镜像构建文件
│   └── bin/                   # 编译输出目录（linux 二进制）
├── scripts/                    # 构建脚本
│   ├── proto/
│   │   └── protoc.sh          # 生成 protobuf 代码到 protogen/
│   ├── server/
│   │   ├── binary.sh          # 编译 server 二进制
│   │   └── build.sh           # 构建 server Docker 镜像
│   ├── client/
│   │   ├── binary.sh          # 编译 client 二进制
│   │   └── build.sh           # 构建 client Docker 镜像
│   └── kind/
│       └── load.sh            # 加载镜像到 kind 集群
├── deploy/                     # Kubernetes 部署文件
│   ├── server/
│   │   ├── service.yaml       # ClusterIP Service (端口 9000)
│   │   └── deployment.yaml    # Server Deployment (3 副本，Downward API)
│   └── client/
│       └── deployment.yaml    # Client Deployment (循环压测)
├── go.mod                      # Go 模块定义
├── Makefile                    # 统一构建入口
└── README.md                   # 本文档
```

## 快速开始

### 前置要求

- Go 1.21+
- Docker
- kind（用于本地 Kubernetes 集群）
- kubectl
- protoc（Protocol Buffers 编译器）

### 使用 Makefile（推荐）

```bash
# 查看所有可用命令
make help

# 完整构建并部署到 kind
make all

# 或者分步执行
make proto           # 生成 protobuf 代码
make binaries        # 编译 server 和 client 二进制
make images          # 构建 Docker 镜像
make kind-load       # 加载镜像到 kind
make deploy          # 部署到 Kubernetes
```

### 查看结果

```bash
# 查看 client 日志（实时压测统计）
make logs-client

# 查看 server 日志
make logs-server

# 查看部署状态
make status
```

## 本地开发与测试

### 本地运行

```bash
# 1. 生成 proto 代码
make proto

# 2. 在一个终端运行 server
make run-server

# 3. 在另一个终端运行 client
make run-client
```

### 快速本地测试

```bash
# 自动启动 server、运行 client、然后清理
make test-local
```

### 本地调试 kind

```bash
kubectl get svc -n test
kubectl get pod -n test
kubectl logs grpc-server-xxxxxxxxxx-xxxxx -f -n test
kubectl port-forward svc/grpc-server -n test 9000:9000

grpcurl -plaintext localhost:9000 list
grpcurl -plaintext localhost:9000 describe echo.Echo
grpcurl -plaintext -d '{"message": "hello"}' localhost:9000 echo.Echo/Echo
```

## 构建流程详解

### 1. 生成 Protobuf 代码

```bash
make proto
# 或
./scripts/proto/protoc.sh
```

- 自动检查并安装 `protoc-gen-go` 和 `protoc-gen-go-grpc`
- 从 `proto/echo.proto` 生成代码到 `protogen/echo/`
- server 和 client 都导入 `github.com/hj24/grpc-lb-test/protogen/echo`

### 2. 构建 Docker 镜像

```bash
make server-image     # grpc-lb-test-server:latest
make client-image     # grpc-lb-test-client:latest
# 或
make images           # 同时构建两个镜像
```

- **注意**：二进制在 Docker 构建时编译（多阶段构建）
- 第一阶段：golang:1.24-alpine 镜像中编译二进制
- 第二阶段：将二进制复制到 alpine:latest 精简镜像
- 镜像名和 tag 可通过环境变量覆盖

### 3. 加载到 kind

```bash
make kind-load
# 或
./scripts/kind/load.sh
```

- 默认加载到名为 `kind` 的集群
- 可通过 `KIND_CLUSTER=my-cluster make kind-load` 指定集群名

### 4. 部署到 Kubernetes

```bash
make deploy-server    # 部署 server（Service + Deployment）
make deploy-client    # 部署 client（Deployment）
# 或
make deploy           # 同时部署两者
```

- 默认部署到 `test` namespace
- server：3 副本，通过 Downward API 注入 `POD_NAME` 和 `POD_IP`
- client：1 副本，循环压测（每 30 秒发送 1000 个请求）

## gRPC 服务接口

### Echo 方法

- **服务名**：`echo.Echo`
- **方法名**：`Echo`
- **请求**：
  ```json
  {
    "message": "your message"
  }
  ```
- **响应**：
  ```json
  {
    "message": "your message",
    "hostname": "grpc-server-xxx",
    "pod_name": "grpc-server-xxx",
    "pod_ip": "10.244.x.x"
  }
  ```

## Client 参数

client 支持以下命令行参数（也可以通过 deploy/client/deployment.yaml 配置）：

```bash
-target       string   # gRPC 服务地址（默认：grpc-server.test.svc.cluster.local:9000）
-total        int      # 每轮请求总数（默认：1000）
-concurrency  int      # 并发 worker 数（默认：50）
-conns        int      # gRPC 连接数（默认：3）
-timeout      duration # 单次请求超时（默认：10s）
-loop         bool     # 是否循环压测（默认：false）
-interval     duration # 循环间隔（默认：10s）
-verbose      bool     # 是否打印每个响应（默认：false）
```

示例：

```bash
# 本地测试
go run ./client -target localhost:9000 -total 100 -concurrency 10 -conns 3

# 在 k8s 中测试单次
kubectl run test-client --rm -it --image=grpc-lb-test-client:latest --restart=Never \
  -- -target grpc-server.test.svc.cluster.local:9000 -total 500 -concurrency 20 -conns 5
```

## 观察负载均衡

### 现象

当使用较少的连接数（如 `--conns 1-3`）时，由于 HTTP/2 连接复用，大部分请求可能会落到少数几个 Pod，导致负载不均衡。

### 验证方法

```bash
# 查看 client 日志中的 Pod 分布统计
make logs-client
```

输出示例：

```
=== Pod Distribution ===
    850 (85.0%) - grpc-server-7d4f8b9c6-abc12 (10.244.1.5)
    120 (12.0%) - grpc-server-7d4f8b9c6-def34 (10.244.1.6)
     30 ( 3.0%) - grpc-server-7d4f8b9c6-ghi56 (10.244.1.7)

Total requests: 1000
Unique pods:    3
```

### 改善方法

1. **增加连接数**：修改 `deploy/client/deployment.yaml` 中的 `-conns` 参数
2. **使用 Headless Service + 客户端负载均衡**：需要应用层实现
3. **使用 Service Mesh**（如 Istio、Linkerd）：自动处理 gRPC 负载均衡

## Makefile 命令总览

| 命令 | 说明 |
|------|------|
| `make help` | 显示所有可用命令 |
| `make proto` | 生成 protobuf 代码 |
| `make server-binary` | 编译 server 二进制（本地测试用） |
| `make client-binary` | 编译 client 二进制（本地测试用） |
| `make binaries` | 编译 server 和 client 二进制（本地测试用） |
| `make server-image` | 构建 server Docker 镜像（容器内编译） |
| `make client-image` | 构建 client Docker 镜像（容器内编译） |
| `make images` | 构建 server 和 client Docker 镜像 |
| `make kind-load` | 加载镜像到 kind 集群 |
| `make deploy-server` | 部署 gRPC server |
| `make deploy-client` | 部署 gRPC client |
| `make deploy` | 部署 server 和 client |
| `make undeploy` | 删除所有部署 |
| `make logs-server` | 查看 server 日志 |
| `make logs-client` | 查看 client 日志 |
| `make status` | 查看部署状态 |
| `make clean` | 清理构建产物 |
| `make all` | 完整构建并部署 |
| `make run-server` | 本地运行 server |
| `make run-client` | 本地运行 client |
| `make test-local` | 本地快速测试 |

## 修改代码后重新部署

```bash
# 快速重建并部署
make all

# 或分步执行
make images           # 重新构建镜像（会在容器内重新编译）
make kind-load        # 重新加载镜像到 kind
kubectl rollout restart deployment/grpc-server -n test
kubectl rollout restart deployment/grpc-client -n test
```

## 清理

```bash
# 清理构建产物（二进制、生成的 proto 代码）
make clean

# 删除 Kubernetes 部署
make undeploy

# 删除 namespace（可选）
kubectl delete namespace test
```

## 故障排查

### Pod 无法启动

```bash
# 查看 Pod 状态
kubectl get pods -n test

# 查看 Pod 日志
kubectl logs -n test -l app=grpc-server
kubectl logs -n test -l app=grpc-client

# 查看 Pod 详情
kubectl describe pod -n test <pod-name>
```

### 镜像拉取失败

kind 集群使用本地镜像，确保：

1. 镜像已构建：`docker images | grep grpc-lb-test`
2. 镜像已加载到 kind：`make kind-load`
3. deployment.yaml 中 `imagePullPolicy: Never`

### 连接被拒绝

```bash
# 检查 Service
kubectl get svc -n test grpc-server

# 检查 Endpoints
kubectl get endpoints -n test grpc-server

# 测试集群内连接
kubectl run -it --rm debug --image=alpine --restart=Never -n test -- \
  sh -c "apk add --no-cache curl && curl -v telnet://grpc-server.test.svc.cluster.local:9000"
```

## 进阶使用

### 使用 ghz 压测（可选）

安装 ghz：

```bash
go install github.com/bojand/ghz/cmd/ghz@latest
```

压测示例：

```bash
# 端口转发
kubectl port-forward -n test svc/grpc-server 9000:9000

# 在另一个终端运行 ghz
ghz --insecure \
  --call echo.Echo/Echo \
  --data '{"message":"test"}' \
  --concurrency 50 \
  --connections 3 \
  --total 10000 \
  localhost:9000
```

### 调整 server 副本数

```bash
# 方法 1：编辑 deployment.yaml
vim deploy/server/deployment.yaml  # 修改 replicas
make deploy-server

# 方法 2：直接 scale
kubectl scale deployment grpc-server -n test --replicas=5
```

### 修改 client 压测参数

编辑 `deploy/client/deployment.yaml` 中的 `args` 部分：

```yaml
args:
- "-target=grpc-server.test.svc.cluster.local:9000"
- "-total=5000"        # 每轮请求数
- "-concurrency=100"   # 并发数
- "-conns=10"          # 连接数（关键参数！）
- "-loop=true"
- "-interval=60s"
```

然后重新部署：

```bash
kubectl apply -f deploy/client/deployment.yaml
kubectl rollout restart deployment/grpc-client -n test
```

## License

MIT
