#!/bin/bash
# X-UI Clean Install Script (No ads / No promotion)

set -e

install_dir="/usr/local/x-ui"
service_file="/etc/systemd/system/x-ui.service"

echo "=============================="
echo "   X-UI Clean Install Script  "
echo "         (No Ads)             "
echo "=============================="
echo

# -------------------------------
# 1. 安装依赖
# -------------------------------
if [ -f /etc/debian_version ]; then
    apt update -y
    apt install -y curl wget tar socat
elif [ -f /etc/redhat-release ]; then
    yum install -y curl wget tar socat
else
    echo "Unsupported OS"
    exit 1
fi

# -------------------------------
# 2. 下载 X-UI 最新版本
# -------------------------------
latest_version="v25.11.11"
url="https://github.com/xeefei/x-panel/releases/download/${latest_version}/x-ui-linux-amd64.tar.gz"

echo "下载 X-UI..."
wget -O /usr/local/x-ui-linux-amd64.tar.gz "$url"

mkdir -p $install_dir
tar -zxvf /usr/local/x-ui-linux-amd64.tar.gz -C $install_dir
chmod +x $install_dir/x-ui

# -------------------------------
# 3. 创建服务
# -------------------------------
cat > $service_file <<EOF
[Unit]
Description=X-UI Service
After=network.target

[Service]
Type=simple
ExecStart=$install_dir/x-ui
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable x-ui
systemctl restart x-ui

# -------------------------------
# 4. 生成随机账号密码与路径
# -------------------------------
USER_RANDOM=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
PASS_RANDOM=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 18)
PATH_RANDOM=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

config_file="/usr/local/x-ui/bin/config.json"

sed -i "s|\"username\":.*|\"username\": \"$USER_RANDOM\",|" $config_file
sed -i "s|\"password\":.*|\"password\": \"$PASS_RANDOM\",|" $config_file
sed -i "s|\"webBasePath\":.*|\"webBasePath\": \"/$PATH_RANDOM\",|" $config_file

systemctl restart x-ui

# -------------------------------
# 5. 输出信息
# -------------------------------
echo
echo "=========== X-UI 安装完成 (Clean Version) ==========="
echo "地址（HTTP）: http://服务器IP:13688/$PATH_RANDOM/"
echo "账号: $USER_RANDOM"
echo "密码: $PASS_RANDOM"
echo "路径: /$PATH_RANDOM/"
echo
echo "如需重新查看，可执行：cat $config_file"
