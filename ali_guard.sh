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

if ! command -v docker &> /dev/null; then
    echo -e "${RED}[错误] 未检测到 Docker，请先安装 Docker！${NC}"
    exit 1
fi

mkdir -p "${DATA_DIR}"

# 1. 检查与更新源码
if [ ! -d "${SRC_DIR}/.git" ]; then
    echo -e "${YELLOW}正在克隆 Aliyun-Guard 仓库...${NC}"
    git clone "${REPO_URL}" "${SRC_DIR}"
else
    echo -e "${YELLOW}正在检查并更新源码...${NC}"
    cd "${SRC_DIR}" && git pull || true
fi

cd "${SRC_DIR}"

# 2. 确保 Dockerfile 存在
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}[错误] 未在仓库中找到 Dockerfile！${NC}"
    exit 1
fi

echo -e "${YELLOW}正在构建 Docker 镜像...${NC}"
docker build -t "${IMAGE_NAME}" .

# 3. 清理旧容器
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e "${YELLOW}正在清理旧容器...${NC}"
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo -e "${GREEN}正在启动 Aliyun-Guard 容器...${NC}"

# 4. 优化启动：使用标准伪终端并挂载数据目录，同时保持容器存活
docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart always \
    -p "${HOST_PORT}:${HOST_PORT}" \
    -e TZ=Asia/Shanghai \
    -v "${DATA_DIR}:/app/data" \
    --entrypoint bash \
    "${IMAGE_NAME}" \
    -c "while true; do sleep 3600; done"

echo -e "${GREEN}✅ 容器启动成功！正在进入交互菜单...${NC}"
sleep 1

# 5. 进入容器内部执行原版安装/管理脚本
docker exec -it "${CONTAINER_NAME}" bash -c "if [ -f 'install.sh' ]; then ./install.sh; elif [ -f 'run.sh' ]; then ./run.sh; else bash; fi"
EOF
