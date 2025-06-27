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

# 确定系统类型并执行系统更新命令
echo "[1/8] 确定系统类型并执行更新命令..."
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu系统
    echo "检测到 Debian/Ubuntu 系统，执行 apt 更新..."
    sudo apt update -y && sudo apt install -y curl && sudo apt install -y socat
    # 给安装一些时间，但不必太长
    sleep 5  
elif [ -f /etc/redhat-release ]; then
    # CentOS系统
    echo "检测到 CentOS 系统，执行 yum 更新..."
    sudo yum update -y && sudo yum install -y socat
    sleep 5
else
    echo "未知的操作系统，无法自动处理系统更新。"
    exit 1
fi

# 安装 X-UI 面板，并自动输入【n】来保留旧设置
echo "[2/8] 安装 X-UI 面板..."
bash <(curl -Ls https://raw.githubusercontent.com/xeefei/3x-ui/master/install.sh) <<EOF
n
EOF
# 减少安装后的等待时间
sleep 5  

# 确保安装成功后，执行后续操作
echo "[3/8] X-UI 面板安装完成，继续执行后续操作..."

# 将脚本转换为 Unix 风格
echo "[4/8] 转换文件格式为 Unix 风格..."
dos2unix /root/zidong.sh
echo "文件格式已转换为 Unix 格式。"
# 去除不必要的等待时间，执行完后继续
sleep 2  

# 使用 sed 命令去除回车符（\r）
echo "[5/8] 去除脚本中的回车符..."
sed -i 's/\r//' /root/zidong.sh
echo "回车符已去除。"
sleep 2  

# 赋予脚本执行权限
echo "[6/8] 赋予脚本执行权限..."
chmod +x /root/zidong.sh
echo "脚本已赋予执行权限。"
sleep 2  

# 检查并安装依赖
echo "[7/8] 确认依赖是否安装..."
if ! command -v expect &>/dev/null; then
    echo "未检测到 expect，正在安装..."
    sudo apt update && sudo apt install -y expect
    sleep 5  # 安装完成后继续
else
    echo "expect 已安装。"
fi

# 检查防火墙工具
echo "[8/8] 检查防火墙工具..."
if command -v ufw &>/dev/null; then
    echo "防火墙使用 ufw 管理，开启端口..."
    sudo ufw allow 80,443,2053/tcp
    sudo ufw reload
    echo "端口已开放：80, 443, 2053"
    sleep 3  # 等待防火墙配置生效
elif command -v iptables &>/dev/null; then
    echo "防火墙使用 iptables 管理，开启端口..."
    sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    sudo iptables -I INPUT -p tcp --dport 2053 -j ACCEPT
    sudo service iptables save
    sudo systemctl restart iptables
    echo "端口已开放：80, 443, 2053"
    sleep 3  
else
    echo "没有找到防火墙工具，跳过防火墙配置。"
fi

# 确保防火墙规则生效
echo "[9/8] 确保防火墙规则生效..."
if command -v ufw &>/dev/null; then
    echo "防火墙使用 ufw 管理，确保规则生效..."
    sudo ufw reload
    sleep 2  
elif command -v iptables &>/dev/null; then
    echo "防火墙使用 iptables 管理，确保规则生效..."
    sudo service iptables restart
    sleep 2  
else
    echo "没有防火墙工具，跳过防火墙规则检查。"
fi

# 检查 X-UI 是否已经启动
echo "[10/8] 检查 X-UI 是否已经启动..."
if pgrep -x "x-ui" > /dev/null; then
    echo "X-UI 已经运行！"
else
    echo "X-UI 未运行，尝试启动..."
    sudo systemctl start x-ui
    sleep 3  # 等待 X-UI 启动
    echo "X-UI 已启动！"
fi

# 安装 SSL 证书...
echo "[11/8] 安装 SSL 证书..."
# 确保 acme.sh 已安装
if ! command -v acme.sh &>/dev/null; then
    echo "未检测到 acme.sh，正在安装..."
    curl https://get.acme.sh | sh
    sleep 5  # 确保安装完成后继续
else
    echo "acme.sh 已安装。"
fi

# 执行证书注册函数
register_certificate

# 设置 Let's Encrypt 作为 CA 来生成证书
echo "[12/8] 使用 Let's Encrypt 生成证书..."
~/.acme.sh/acme.sh --set-default-ca --ca-url https://acme-v02.api.letsencrypt.org/directory
sleep 2  

# 根据域名自动生成证书
echo -e "\033[33m请输入您的域名（例如: zidong.goudan521.sbs）：\033[0m"
read DOMAIN

echo "正在为域名 $DOMAIN 生成 SSL 证书..."
~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --key-file "/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.key" --cert-file "/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.cer"
sleep 10  # 给证书生成充足时间

echo "SSL 证书已成功生成！"

# 配置证书路径...
echo "[13/8] 配置 X-UI 使用 SSL 证书..."
XUI_CERT_PATH="/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.cer"
XUI_KEY_PATH="/root/.acme.sh/$DOMAIN_ecc/$DOMAIN.key"

# 确保路径正确并配置
if [[ -f "$XUI_CERT_PATH" && -f "$XUI_KEY_PATH" ]]; then
    echo "证书和密钥路径配置正确，开始应用配置..."
    sudo systemctl restart x-ui
    sleep 3  
    echo "证书已成功配置到 X-UI。"
else
    echo "错误：证书文件或密钥文件未找到，请检查路径是否正确。"
    exit 1
fi

# 新增的步骤：启用 BBR
echo "[14/8] 启用 BBR..."
# 使用 x-ui 命令进入面板，输入 22 和 1 来启用 BBR
x-ui <<EOF
22
1
EOF
sleep 3  # 等待 BBR 启动完成

# 检查 BBR 是否启用
echo "[15/8] 检查 BBR 是否启用..."
sysctl net.ipv4.tcp_available_congestion_control
sleep 2  

# 脚本结束信息
echo "=========== 安装完成 ==========="
echo "3X-UI面板和Xray启动成功！"
echo "----------------------------------------------"
echo "---->>> 以下为面板重要信息，请自行记录保存 <<<----"
echo "================================="
echo "警告：请立即登录面板修改默认密码！"
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
echo "版本: v2.5"
echo "============================================="
