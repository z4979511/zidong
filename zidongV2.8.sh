#!/bin/bash

# 定义最大重试次数
MAX_RETRIES=5
RETRY_COUNT=0

# 定义一个函数来执行证书注册步骤
register_certificate() {
    if [[ $RETRY_COUNT -ge $MAX_RETRIES ]]; then
        echo "重试次数达到上限，退出脚本。"
        exit 1
    fi

    echo -e "\033[33m请输入您的邮箱地址（例如: your-email@example.com）：\033[0m"
    read EMAIL
    echo "正在为您的帐户注册..."

    # 注册账户并检查是否成功
    ~/.acme.sh/acme.sh --register-account -m "$EMAIL"
    
    # 检查是否注册成功，如果失败则要求重新输入邮箱
    if grep -q "Could not get nonce" ~/.acme.sh/acme.sh.log; then
        echo "注册失败：获取 nonce 时出错，请重新输入邮箱。"
        ((RETRY_COUNT++))  # 计数器增加
        register_certificate  # 递归调用函数重新输入邮箱
    else
        echo "账户注册成功！"
    fi
}

# 系统更新
echo "[1/8] 确定系统类型并执行更新命令..."
if [ -f /etc/debian_version ]; then
    echo "检测到 Debian/Ubuntu 系统，执行 apt 更新..."
    sudo apt update -y && sudo apt install -y curl socat dos2unix expect
elif [ -f /etc/redhat-release ]; then
    echo "检测到 CentOS 系统，执行 yum 更新..."
    sudo yum update -y && sudo yum install -y socat curl dos2unix expect
else
    echo "未知的操作系统，无法自动处理系统更新。"
    exit 1
fi

# ==================== 安装 X-UI 面板 ====================
echo "[2/8] 安装 X-UI 面板（自动选择免费基础版）..."
bash <(curl -Ls https://raw.githubusercontent.com/xeefei/3x-ui/master/install.sh) <<EOF
1
EOF
sleep 5

# ==================== 后续操作 ====================
echo "[3/8] X-UI 面板安装完成，继续执行后续操作..."

# 转换文件格式
echo "[4/8] 转换脚本为 Unix 格式..."
dos2unix /root/zidong.sh
sed -i 's/\r//' /root/zidong.sh
chmod +x /root/zidong.sh
sleep 2

# 防火墙设置
echo "[5/8] 检查防火墙工具并开放端口..."
if command -v ufw &>/dev/null; then
    sudo ufw allow 80,443,2053/tcp
    sudo ufw reload
elif command -v iptables &>/dev/null; then
    sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport 2053 -j ACCEPT
    sudo service iptables save
    sudo systemctl restart iptables
fi
sleep 2

# 检查 X-UI 是否启动
echo "[6/8] 检查 X-UI 是否已启动..."
if ! pgrep -x "x-ui" > /dev/null; then
    sudo systemctl start x-ui
    sleep 3
fi

# 安装 acme.sh 并注册证书
echo "[7/8] 安装 acme.sh 并注册证书..."
if ! command -v acme.sh &>/dev/null; then
    curl https://get.acme.sh | sh
    sleep 5
fi
register_certificate

# 生成 SSL 证书
echo -e "\033[33m请输入您的域名（例如: zidong.goudan521.sbs）：\033[0m"
read DOMAIN
~/.acme.sh/acme.sh --set-default-ca --ca-url https://acme-v02.api.letsencrypt.org/directory
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" \
    --key-file "/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.key" \
    --cert-file "/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.cer"
sleep 5

# 配置 X-UI 使用证书
XUI_CERT_PATH="/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.cer"
XUI_KEY_PATH="/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.key"
if [[ -f "$XUI_CERT_PATH" && -f "$XUI_KEY_PATH" ]]; then
    sudo systemctl restart x-ui
fi

# 启用 BBR
echo "[8/8] 启用 BBR..."
x-ui <<EOF
22
1
EOF
sleep 2

# 完成信息
echo "=========== 安装完成 ==========="
echo "3X-UI面板和Xray启动成功！"
echo "请使用命令 x-ui -> 10 查看面板随机生成的账号和密码"
