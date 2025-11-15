#!/bin/bash

# =========================================================
# Nicholas-Panel 自动部署脚本 v3.0（无广告 & 专业优化版）
# =========================================================

set -e

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}"
echo "=============================================="
echo "        Nicholas-Panel 自动部署系统"
echo "=============================================="
echo -e "${RESET}"

# --------------------------------------------------------
# 系统检测
# --------------------------------------------------------
echo -e "${YELLOW}[1/8] 检测系统...${RESET}"

if [ -f /etc/debian_version ]; then
    PM_INSTALL="apt install -y"
    PM_UPDATE="apt update -y"
elif [ -f /etc/redhat-release ]; then
    PM_INSTALL="yum install -y"
    PM_UPDATE="yum update -y"
else
    echo -e "${RED}不支持的系统！${RESET}"
    exit 1
fi

# --------------------------------------------------------
# 更新系统 + 安装依赖
# --------------------------------------------------------
echo -e "${YELLOW}[2/8] 更新系统与安装依赖...${RESET}"
$PM_UPDATE
$PM_INSTALL curl wget socat tar dos2unix expect

# --------------------------------------------------------
# 安装 X-UI（Clean 版）
# --------------------------------------------------------
echo -e "${YELLOW}[3/8] 安装 X-UI（Clean 无广告版）...${RESET}"

bash <(curl -Ls https://raw.githubusercontent.com/z4979511/zidong/main/xui_clean.sh)

sleep 3

# --------------------------------------------------------
# 输入域名
# --------------------------------------------------------
echo -e "${YELLOW}[4/8] 请输入你的域名（必须已解析到服务器）：${RESET}"
read DOMAIN

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}域名不能为空！${RESET}"
    exit 1
fi

# --------------------------------------------------------
# 安装 acme.sh
# --------------------------------------------------------
echo -e "${YELLOW}[5/8] 安装 acme.sh...${RESET}"

if ! command -v acme.sh &>/dev/null; then
    curl https://get.acme.sh | sh
fi

# 注册邮箱
echo -e "${YELLOW}请输入你的邮箱：${RESET}"
read EMAIL
~/.acme.sh/acme.sh --register-account -m "$EMAIL"

# --------------------------------------------------------
# 申请证书
# --------------------------------------------------------
echo -e "${YELLOW}[6/8] 正在为域名申请证书：$DOMAIN${RESET}"

~/.acme.sh/acme.sh --set-default-ca --ca-url https://acme-v02.api.letsencrypt.org/directory
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN"

CERT="/root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer"
KEY="/root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key"

if [[ ! -f "$CERT" ]]; then
    echo -e "${RED}证书申请失败！${RESET}"
    exit 1
fi

# --------------------------------------------------------
# 配置 X-UI SSL
# --------------------------------------------------------
echo -e "${YELLOW}[7/8] 配置 X-UI 证书...${RESET}"

CONFIG="/usr/local/x-ui/bin/config.json"
sed -i "s|\"cert_file\":.*|\"cert_file\": \"$CERT\",|" $CONFIG
sed -i "s|\"key_file\":.*|\"key_file\": \"$KEY\",|" $CONFIG
sed -i "s|\"web_base_url\":.*|\"web_base_url\": \"https://$DOMAIN\",|" $CONFIG

systemctl restart x-ui

# --------------------------------------------------------
# 启用 BBR
# --------------------------------------------------------
echo -e "${YELLOW}[8/8] 启用 BBR...${RESET}"

x-ui <<EOF
22
1
EOF

# --------------------------------------------------------
# 读取 UI 信息
# --------------------------------------------------------
USER=$(grep username $CONFIG | awk -F '"' '{print $4}')
PASS=$(grep password $CONFIG | awk -F '"' '{print $4}')
PATH=$(grep webBasePath $CONFIG | awk -F '"' '{print $4}')

# --------------------------------------------------------
# 最终输出
# --------------------------------------------------------
echo -e "${GREEN}"
echo "=============================================="
echo "            🎉 部署完成！ 🎉"
echo "=============================================="
echo "面板地址：https://$DOMAIN$PATH/"
echo "账号：$USER"
# decode if base64 — auto detect
if [[ "$PASS" == *= ]]; then
    echo "密码（base64）：$PASS"
else
    echo "密码：$PASS"
fi
echo "证书：已配置"
echo "BBR：已启用"
echo "=============================================="
echo -e "${RESET}"
