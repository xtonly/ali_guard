cat << 'EOF' > ali_guard.sh
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

echo -e "${GREEN}=== Aliyun-Guard Docker 自动部署/更新脚本 (端口: ${HOST_PORT}) ===${NC}"

# 1. 检查 Docker 与 Git 环境
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[错误] 未检测到 Docker，请先安装 Docker！${NC}"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}[提示] 正在安装 git...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y git
    elif command -v yum &> /dev/null; then
        yum install -y git
    fi
fi

# 2. 创建持久化目录与拉取/更新源码
mkdir -p "${DATA_DIR}"

if [ -d "${SRC_DIR}/.git" ]; then
    echo -e "${YELLOW}[1/4] 检测到已有源码，正在拉取最新代码进行更新...${NC}"
    cd "${SRC_DIR}"
    git fetch --all
    git reset --hard origin/$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
    git pull
else
    echo -e "${YELLOW}[1/4] 正在克隆 Aliyun-Guard 仓库...${NC}"
    rm -rf "${SRC_DIR}"
    git clone "${REPO_URL}" "${SRC_DIR}"
    cd "${SRC_DIR}"
fi

# 3. 构建最新 Docker 镜像
echo -e "${YELLOW}[2/4] 正在构建 Docker 镜像...${NC}"
if [ -f "Dockerfile" ]; then
    docker build -t "${IMAGE_NAME}" .
else
    echo -e "${RED}[错误] 仓库中未找到 Dockerfile，请检查仓库结构！${NC}"
    exit 1
fi

# 4. 自动探测容器内部端口与需要持久化的数据目录
echo -e "${YELLOW}[3/4] 正在解析容器端口与数据持久化路径...${NC}"

# 从 Dockerfile 提取 EXPOSE 端口（若未声明则默认回退至 8080/5000/8000 探测）
INTERNAL_PORT=$(grep -i "^EXPOSE" Dockerfile | awk '{print $2}' | tr -d '\r' | head -n 1)
if [ -z "${INTERNAL_PORT}" ]; then
    # 尝试从原仓库的 docker-compose.yml 提取内部端口
    if [ -f "docker-compose.yml" ]; then
        INTERNAL_PORT=$(grep -E "\-[[:space:]]*\"?[0-9]+:[0-9]+\"?" docker-compose.yml | head -n 1 | awk -F':' '{print $2}' | tr -d '" \r')
    fi
fi
INTERNAL_PORT=${INTERNAL_PORT:-8080}
echo -e " -> 识别到容器内部端口为: ${GREEN}${INTERNAL_PORT}${NC}，将映射至宿主机端口: ${GREEN}${HOST_PORT}${NC}"

# 提取工作目录 WORKDIR (默认 /app)
WORKDIR=$(grep -i "^WORKDIR" Dockerfile | tail -n 1 | awk '{print $2}' | tr -d '\r')
WORKDIR=${WORKDIR:-/app}

# 准备挂载参数：确保常见的数据、配置、日志目录及 SQLite/JSON 文件全部持久化保存
VOLUME_ARGS=""

# 如果首次安装且源码带有默认配置目录，先同步到持久化目录避免空目录覆盖报错
for SUBDIR in data config logs db; do
    mkdir -p "${DATA_DIR}/${SUBDIR}"
    # 若镜像内该目录存在初始文件，首次运行时通过临时容器拷贝出来以保留默认模板
    if [ -z "$(ls -A "${DATA_DIR}/${SUBDIR}" 2>/dev/null)" ]; then
        docker run --rm --entrypoint sh "${IMAGE_NAME}" -c "if [ -d '${WORKDIR}/${SUBDIR}' ]; then cp -rn ${WORKDIR}/${SUBDIR}/. /tmp_out/ 2>/dev/null || true; fi" -v "${DATA_DIR}/${SUBDIR}:/tmp_out" 2>/dev/null || true
    fi
done

# 检查原仓库 docker-compose.yml 中是否有特定挂载声明，否则挂载标准持久化目录
VOLUME_ARGS="-v ${DATA_DIR}/data:${WORKDIR}/data -v ${DATA_DIR}/config:${WORKDIR}/config -v ${DATA_DIR}/logs:${WORKDIR}/logs"

# 如果项目使用根目录下的 config.json / data.json，也做软链接或挂载保护
for CFG_FILE in config.json config.yaml data.db guard.db; do
    if [ -f "${SRC_DIR}/${CFG_FILE}" ] && [ ! -f "${DATA_DIR}/${CFG_FILE}" ]; then
        cp "${SRC_DIR}/${CFG_FILE}" "${DATA_DIR}/${CFG_FILE}"
    fi
    if [ -f "${DATA_DIR}/${CFG_FILE}" ]; then
        VOLUME_ARGS="${VOLUME_ARGS} -v ${DATA_DIR}/${CFG_FILE}:${WORKDIR}/${CFG_FILE}"
    fi
done

# 5. 停止旧容器并启动新容器（保留全部挂载数据）
echo -e "${YELLOW}[4/4] 正在重启容器并应用最新镜像...${NC}"
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    echo -e " -> 停止并移除旧容器 ${CONTAINER_NAME}（宿主机数据完全保留）..."
    docker stop "${CONTAINER_NAME}" >/dev/null
    docker rm "${CONTAINER_NAME}" >/dev/null
fi

docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart always \
    -p "${HOST_PORT}:${INTERNAL_PORT}" \
    -e TZ=Asia/Shanghai \
    -e PORT="${INTERNAL_PORT}" \
    ${VOLUME_ARGS} \
    "${IMAGE_NAME}"

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}✅ 部署/更新完成！${NC}"
echo -e "🌐 Web 面板访问地址: ${YELLOW}http://您的服务器IP:${HOST_PORT}${NC}"
echo -e "📂 持久化数据保存路径: ${YELLOW}${DATA_DIR}${NC}"
echo -e "🔄 后续如何更新(保留数据): 直接再次运行 ${YELLOW}bash ali_guard.sh${NC} 即可！"
echo -e "${GREEN}======================================================${NC}"
EOF

chmod +x manage_aliyun_guard.sh
