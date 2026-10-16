#!/bin/bash
set -e

# ==================== 配置区域 ====================
REPO_URL="https://github.com/Felix666-ship-It/aliyun-guard.git"
BASE_DIR="/opt/aliyun-guard"
SRC_DIR="${BASE_DIR}/source"
DATA_DIR="${BASE_DIR}/persistent_data"
CONTAINER_NAME="aliyun-guard"
IMAGE_NAME="aliyun-guard:latest"
HOST_PORT="13210"
# ==================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查环境
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[错误] 未检测到 Docker，请先安装 Docker！${NC}"
    exit 1
fi

mkdir -p "${DATA_DIR}"

# 1. 首次拉取或更新源码
if [ ! -d "${SRC_DIR}/.git" ]; then
    echo -e "${YELLOW}正在克隆 Aliyun-Guard 仓库...${NC}"
    git clone "${REPO_URL}" "${SRC_DIR}"
else
    echo -e "${YELLOW}正在检查并更新源码...${NC} "
    cd "${SRC_DIR}" && git pull || true
fi

# 2. 构建镜像（如果还没有）
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo -e "${YELLOW}正在首次构建 Docker 镜像...${NC}"
    cd "${SRC_DIR}"
    docker build -t "${IMAGE_NAME}" .
fi

# 3. 准备数据挂载目录
INTERNAL_PORT="13210"
VOLUME_MAP="-v ${DATA_DIR}:/app/data" # 根据原版结构映射持久化目录

# 如果容器已经在运行，直接进入其交互菜单
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    docker exec -it "${CONTAINER_NAME}" bash
    exit 0
fi

# 如果容器存在但停止了，先删除旧容器
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo -e "${GREEN}正在启动 Aliyun-Guard 容器并打开交互菜单...${NC}"

# 4. 以交互式(-it)且绑定端口的方式启动容器，完美支持原版菜单与网页端
docker run -it \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:${HOST_PORT}" \
    -e TZ=Asia/Shanghai \
    -v "${DATA_DIR}:/app/data" \
    "${IMAGE_NAME}"
EOF
