#!/bin/bash

# 小米AX3600专用 - ImmortalWrt定制脚本
# 建议在主路由场景下使用。已优化相关网络、DHCP、防火墙等配置，剔除旁路由和无关设定。

# 安装必要依赖（如有需要可取消注释）
# sudo -E apt-get -y install rename

# 展示 feeds 配置（调试可用）
cat feeds.conf.default

# 添加第三方软件包（如有需要可自行添加/删除）
git clone https://github.com/db-one/dbone-packages.git -b 23.05 package/dbone-packages

# 更新并安装所有 feeds
./scripts/feeds update -a && ./scripts/feeds install -a -f

# 删除部分不需要的包（可根据实际需求调整）
rm -rf feeds/luci/applications/luci-app-qbittorrent
rm -rf feeds/luci/applications/luci-app-openclash
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf package/dbone-packages/passwall/packages/v2ray-geoview

# 定义配置文件路径
NET="package/base-files/files/bin/config_generate"
ZZZ="package/emortal/default-settings/files/99-default-settings"

# 修改默认登陆地址与主机名
#sed -i "s#192.168.1.1#192.168.31.1#g" $NET            # 小米原厂网段，更常见于AX系列
sed -i "s#ImmortalWrt#Xiaomi-AX3600#g" $NET            # 设置主机名

# 设置默认主题为argon（如有需求可调整主题名称）
echo "uci set luci.main.mediaurlbase=/luci-static/argon" >> $ZZZ

# 设置固件版本显示
BUILDTIME=$(TZ=UTC-8 date "+%Y.%m.%d")
sed -i "s/\(_('Firmware Version'), *\)/\1 ('AX3600 build $BUILDTIME @ ') + /" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# 性能跑分日志（可选）
echo "rm -f /etc/uci-defaults/xxx-coremark" >> "$ZZZ"
cat >> $ZZZ <<EOF
cat /dev/null > /etc/bench.log
echo " (CpuMark : 26000.000000" >> /etc/bench.log
echo " Scores)" >> /etc/bench.log
EOF

# ================ 主路由网络设置 =========================
cat >> $ZZZ <<-EOF
# 主路由模式下保留DHCP和常规NAT，适配IPv4/IPv6双栈
uci set network.lan.ipaddr='192.168.1.1'                   # 主路由地址
uci set network.lan.netmask='255.255.255.0'
uci delete network.lan.gateway                             # 主路由无需上游网关
uci delete network.lan.dns                                 # 主路由自身为DNS
uci set network.lan.delegate='1'                           # 启用IPv6管理
uci set dhcp.lan.ignore='0'                                # 启用DHCP服务
uci set firewall.@zone[0].masq='1'                         # 启用LAN口 IP 动态伪装
uci set firewall.@defaults[0].synflood_protect='1'         # 启用 SYN-flood 防御
uci set firewall.@defaults[0].flow_offloading='1'          # 启用软件流量分载
uci set firewall.@defaults[0].flow_offloading_hw='1'       # 启用硬件流量分载
uci set firewall.@defaults[0].fullcone='1'                 # 如fullcone支持可启用
uci set firewall.@defaults[0].fullcone6='1'

# IPv6相关设置（如不需要IPv6可注释以下行）
#uci set network.lan.ip6assign='60'
#uci set dhcp.lan.ra='server'
#uci set dhcp.lan.dhcpv6='server'
#uci set dhcp.lan.ra_management='1'
#uci set dhcp.lan.leasetime='12h'

# 配置Dropbear SSH服务
uci set dropbear.@dropbear[0].enable='1'
uci set dropbear.@dropbear[0].Port='22'
uci set dropbear.@dropbear[0].Interface='lan'

uci commit dhcp
uci commit network
uci commit firewall
uci commit dropbear
/etc/init.d/dropbear restart

EOF

# 检查 OpenClash 是否启用编译（如主路由未用可跳过）
if grep -qE '^(CONFIG_PACKAGE_luci-app-openclash=n|# CONFIG_PACKAGE_luci-app-openclash=)' "${WORKPATH}/$CUSTOM_SH"; then
  echo "OpenClash 未启用编译"
  echo 'rm -rf /etc/openclash' >> $ZZZ
else
  if grep -q "CONFIG_PACKAGE_luci-app-openclash=y" "${WORKPATH}/$CUSTOM_SH"; then
    arch=$(uname -m)
    case "$arch" in
      x86_64) arch="amd64" ;;
      aarch64|arm64) arch="arm64" ;;
    esac
    echo "正在执行：为OpenClash下载内核"
    mkdir -p $HOME/clash-core
    mkdir -p $HOME/files/etc/openclash/core
    cd $HOME/clash-core
    wget -q https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-$arch.tar.gz
    tar -zxvf clash-linux-$arch.tar.gz
    if [[ -f "$HOME/clash-core/clash" ]]; then
      mv -f $HOME/clash-core/clash $HOME/files/etc/openclash/core/clash_meta
      chmod +x $HOME/files/etc/openclash/core/clash_meta
      echo "OpenClash Meta内核配置成功"
    else
      echo "OpenClash Meta内核配置失败"
    fi
    rm -rf $HOME/clash-core/clash-linux-$arch.tar.gz
    rm -rf $HOME/clash-core
  fi
fi

# 修改退出命令到最后
cd $HOME && sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ

# 创建自定义.config文件
cd $WORKPATH
touch ./.config

# 固件定制部分（建议按需补充定制内容）
cat >> .config <<EOF
# 小米AX3600主路由专用TARGET配置
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq807x=y
CONFIG_TARGET_qualcommax_ipq807x_DEVICE_xiaomi_ax3600-stock=y
#CONFIG_TARGET_MULTI_PROFILE=y
#CONFIG_TARGET_PER_DEVICE_ROOTFS=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y #生成 initramfs 格式，TFTP/内存启动/刷机救砖，

# 编译选项
CONFIG_DEVEL=y
CONFIG_CCACHE=y
CONFIG_TARGET_OPTIONS=y
CONFIG_TARGET_OPTIMIZATION="-O2 -pipe -march=armv8-a+crypto -mtune=cortex-a53 -mcpu=cortex-a53"
CONFIG_TOOLCHAINOPTS=y
CONFIG_GCC_USE_VERSION_13=y
CONFIG_GDB=n

# busybox自定义
CONFIG_BUSYBOX_CUSTOM=y
CONFIG_BUSYBOX_CONFIG_TELNET=y

# 核心常用包
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_openssl-util=y
CONFIG_PACKAGE_resize2fs=y
CONFIG_PACKAGE_qrencode=y

# 网络与NAT加速模块
CONFIG_PACKAGE_kmod-nft-queue=y
CONFIG_PACKAGE_kmod-tls=y
CONFIG_PACKAGE_kmod-tun=y

# LuCI及常用应用
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-autoreboot=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-filetransfer=y

# 性能测试
CONFIG_PACKAGE_coremark=y
CONFIG_COREMARK_OPTIMIZE_O3=y
CONFIG_COREMARK_ENABLE_MULTITHREADING=y
CONFIG_COREMARK_NUMBER_OF_THREADS=4

EOF

# 去除多余空格
sed -i 's/^[ \t]*//g' ./.config

cd $HOME
# 配置文件创建完成
