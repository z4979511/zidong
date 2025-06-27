#!/bin/bash

# 定义最大重试次数
MAX_RETRIES=5
RETRY_COUNT=0

# 日志文件路径
LOG_FILE="/root/cert_install.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 记录日志函数
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# 证书注册函数
register_certificate() {
    if [[ $RETRY_COUNT -ge $MAX_RETRIES ]]; then
        log "${RED}重试次数达到上限，退出脚本。${NC}"
        exit 1
    fi

    echo -e "${YELLOW}请输入您的邮箱地址（例如: your-email@example.com）：${NC}"
    read EMAIL
    log "正在为您的帐户注册..."

    # 注册账户并检查是否成功
    ~/.acme.sh/acme.sh --register-account -m "$EMAIL" >> $LOG_FILE 2>&1
    
    if [ $? -ne 0 ]; then
        log "${YELLOW}注册失败，尝试使用备用CA...${NC}"
        ~/.acme.sh/acme.sh --set-default-ca --server zerossl
        ~/.acme.sh/acme.sh --register-account -m "$EMAIL" >> $LOG_FILE 2>&1
        if [ $? -ne 0 ]; then
            log "${RED}注册失败：获取 nonce 时出错，请检查网络连接。${NC}"
            ((RETRY_COUNT++))
            register_certificate
        fi
    else
        log "${GREEN}账户注册成功！${NC}"
    fi
}

# 确定系统类型并执行系统更新命令
log "[1/8] 确定系统类型并执行更新命令..."
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu系统
    log "检测到 Debian/Ubuntu 系统，执行 apt 更新..."
    sudo apt update -y && sudo apt install -y curl socat dnsutils
    sleep 2
elif [ -f /etc/redhat-release ]; then
    # CentOS系统
    log "检测到 CentOS 系统，执行 yum 更新..."
    sudo yum update -y && sudo yum install -y curl socat bind-utils
    sleep 2
else
    log "${RED}未知的操作系统，无法自动处理系统更新。${NC}"
    exit 1
fi

# 安装 X-UI 面板，并自动输入【n】来保留旧设置
log "[2/8] 安装 X-UI 面板..."
bash <(curl -Ls https://raw.githubusercontent.com/xeefei/3x-ui/master/install.sh) <<EOF
n
EOF
sleep 3

# 确保安装成功后，执行后续操作
log "[3/8] X-UI 面板安装完成，继续执行后续操作..."

# 将脚本转换为 Unix 风格
log "[4/8] 转换文件格式为 Unix 风格..."
if ! command -v dos2unix &>/dev/null; then
    sudo apt install -y dos2unix || sudo yum install -y dos2unix
fi
dos2unix /root/zidong.sh
log "文件格式已转换为 Unix 格式。"
sleep 1

# 使用 sed 命令去除回车符（\r）
log "[5/8] 去除脚本中的回车符..."
sed -i 's/\r//' /root/zidong.sh
log "回车符已去除。"
sleep 1

# 赋予脚本执行权限
log "[6/8] 赋予脚本执行权限..."
chmod +x /root/zidong.sh
log "脚本已赋予执行权限。"
sleep 1

# 检查并安装依赖
log "[7/8] 确认依赖是否安装..."
if ! command -v expect &>/dev/null; then
    log "未检测到 expect，正在安装..."
    sudo apt update && sudo apt install -y expect || sudo yum install -y expect
    sleep 2
else
    log "expect 已安装。"
fi

# 检查防火墙工具
log "[8/8] 检查防火墙工具..."
if command -v ufw &>/dev/null; then
    log "防火墙使用 ufw 管理，开启端口..."
    sudo ufw allow 80,443,2053/tcp
    sudo ufw reload
    log "端口已开放：80, 443, 2053"
    sleep 2
elif command -v iptables &>/dev/null; then
    log "防火墙使用 iptables 管理，开启端口..."
    sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport 2053 -j ACCEPT
    sudo service iptables save
    sudo systemctl restart iptables
    log "端口已开放：80, 443, 2053"
    sleep 2
else
    log "没有找到防火墙工具，跳过防火墙配置。"
fi

# 确保防火墙规则生效
log "[9/8] 确保防火墙规则生效..."
if command -v ufw &>/dev/null; then
    log "防火墙使用 ufw 管理，确保规则生效..."
    sudo ufw reload
    sleep 1
elif command -v iptables &>/dev/null; then
    log "防火墙使用 iptables 管理，确保规则生效..."
    sudo service iptables restart
    sleep 1
else
    log "没有防火墙工具，跳过防火墙规则检查。"
fi

# 检查 X-UI 是否已经启动
log "[10/8] 检查 X-UI 是否已经启动..."
if pgrep -x "x-ui" > /dev/null; then
    log "${GREEN}X-UI 已经运行！${NC}"
else
    log "X-UI 未运行，尝试启动..."
    sudo systemctl start x-ui
    sleep 3
    log "${GREEN}X-UI 已启动！${NC}"
fi

# ==================== 新版证书申请逻辑开始 ====================
log "[11/8] 安装 SSL 证书..."
if ! command -v acme.sh &>/dev/null; then
    log "未检测到 acme.sh，正在安装..."
    curl https://get.acme.sh | sh >> $LOG_FILE 2>&1
    sleep 3
else
    log "acme.sh 已安装。"
fi

# 执行证书注册
register_certificate

# 设置默认CA
log "[12/8] 设置证书颁发机构..."
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 获取域名
echo -e "${YELLOW}请输入您的域名（例如: example.com）：${NC}"
read DOMAIN

# 选择验证方式
echo -e "${YELLOW}请选择验证方式：${NC}"
echo "1) Cloudflare DNS API验证（推荐）"
echo "2) 手动DNS验证（需添加TXT记录）"
read -p "请输入数字选择: " VERIFY_METHOD

case $VERIFY_METHOD in
    1)
        # Cloudflare API验证
        echo -e "${YELLOW}请输入Cloudflare邮箱：${NC}"
        read CF_EMAIL
        echo -e "${YELLOW}请输入Cloudflare Global API Key：${NC}"
        read CF_KEY
        
        export CF_Email="$CF_EMAIL"
        export CF_Key="$CF_KEY"
        
        log "正在使用Cloudflare DNS验证申请证书..."
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" \
            --key-file "/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.key" \
            --cert-file "/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.cer" \
            --fullchain-file "/root/.acme.sh/$DOMAIN_ecc/fullchain.cer" \
            >> $LOG_FILE 2>&1
        ;;
    2)
        # 手动DNS验证
        log "${YELLOW}请按以下步骤操作：${NC}"
        log "1. 接下来会显示需要添加的TXT记录"
        log "2. 请到您的DNS提供商处添加记录"
        log "3. 添加完成后等待DNS生效（通常1-2分钟）"
        log "4. 按回车键继续验证..."
        echo
        ~/.acme.sh/acme.sh --issue --dns -d "$DOMAIN" \
            --yes-I-know-dns-manual-mode-enough-go-ahead-please
        read -p "请确认已添加TXT记录并按回车继续..."
        ~/.acme.sh/acme.sh --renew -d "$DOMAIN" \
            --yes-I-know-dns-manual-mode-enough-go-ahead-please
        ;;
    *)
        log "${RED}无效选择，退出脚本。${NC}"
        exit 1
        ;;
esac

# 验证证书是否生成
XUI_CERT_PATH="/root/.acme.sh/${DOMAIN}_ecc/$DOMAIN.cer"
XUI_KEY_PATH="/root/.acme.sh/${DOMAIN}_ecc/$DOMAIN.key"

if [[ -f "$XUI_CERT_PATH" && -f "$XUI_KEY_PATH" ]]; then
    log "[13/8] 配置 X-UI 使用 SSL 证书..."
    log "证书和密钥路径配置正确，开始应用配置..."
    sudo systemctl restart x-ui
    sleep 3
    log "${GREEN}证书已成功配置到X-UI。${NC}"
else
    log "${RED}错误：证书文件或密钥文件未找到！${NC}"
    log "${YELLOW}可能原因：${NC}"
    log "1. DNS验证未通过（检查TXT记录是否正确）"
    log "2. API密钥权限不足（Cloudflare需要Zone.DNS权限）"
    log "3. 网络连接问题（检查日志: $LOG_FILE）"
    exit 1
fi
# ==================== 新版证书申请逻辑结束 ====================

# 启用BBR
log "[14/8] 启用BBR..."
x-ui <<EOF
22
1
EOF
sleep 3

# 检查BBR状态
log "[15/8] 检查BBR状态..."
sysctl net.ipv4.tcp_available_congestion_control
sleep 2

# 完成信息
echo -e "${GREEN}=========== 安装完成 ===========${NC}"
echo -e "${GREEN}3X-UI面板和Xray启动成功！${NC}"
echo "----------------------------------------------"
echo "---->>> 以下为面板重要信息，请自行记录保存 <<<----"
echo "================================="
echo -e "${RED}警告：请立即登录面板修改默认密码！${NC}"
echo "================================="

# 版权信息
echo "============================================="
echo " 版权声明:"
echo " 1. 允许自由使用和修改"
echo " 2. 禁止用于非法活动"
echo " 3. 二次发布需保留此声明"
echo "============================================="
echo "感谢使用 3X-UI自动化安装工具"
echo "版权声明: 禁止用于商业用途"

# 开发者信息
echo "============================================="
echo "脚本名称: 3X-UI自动化安装工具"
echo "开发者: nicholas-goudan(bilibili)"
echo "联系方式: vx:858737833"
echo -e "${GREEN}版本: v2.6 (DNS验证优化版)${NC}"
echo "============================================="

# 补充说明
echo -e "${YELLOW}=============================================${NC}"
echo -e "${YELLOW}重要提示：${NC}"
echo -e "${YELLOW}1. 如果是Cloudflare API验证失败，请检查：${NC}"
echo "   - Global API Key是否正确"
echo "   - 域名是否在Cloudflare托管"
echo -e "${YELLOW}2. 手动DNS验证失败请检查：${NC}"
echo "   - _acme-challenge TXT记录是否添加正确"
echo "   - DNS是否已传播（等待2-5分钟）"
echo -e "${YELLOW}=============================================${NC}"