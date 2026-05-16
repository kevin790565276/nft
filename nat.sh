#!/bin/bash

# ================= 颜色与 UI 定义 =================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
PURPLE='\033[1;35m'
PLAIN='\033[0m'
BOLD='\033[1m'

SUCCESS="[${GREEN}成功${PLAIN}]"
INFO="[${CYAN}提示${PLAIN}]"
WARN="[${YELLOW}警告${PLAIN}]"
ERROR="[${RED}错误${PLAIN}]"
# ==================================================

base=/etc/dnat
mkdir -p $base 2>/dev/null
conf=$base/conf
touch $conf

# --- 炫彩 Header ---
show_header() {
    clear
    echo -e "${CYAN}╔===============================================================╗${PLAIN}"
    echo -e "${CYAN}║${PLAIN} ${BOLD}${PURPLE} 🚀 nftables NAT 端口转发高级管理工具 (增强炫彩版)       ${PLAIN}${CYAN}║${PLAIN}"
    echo -e "${CYAN}║${PLAIN} ${YELLOW} 特性: 支持单端口 / 自定义端口段 / 智能防冲突 / 一键清理 ${PLAIN}${CYAN}║${PLAIN}"
    echo -e "${CYAN}║${PLAIN} ${CYAN} Based on Arloor | Modified for Perfect Range Forwarding ${PLAIN}${CYAN}║${PLAIN}"
    echo -e "${CYAN}╚===============================================================╝${PLAIN}"
    echo ""
}

setupService(){
    cat > /usr/local/bin/dnat.sh <<"AAAA"
#! /bin/bash
[[ "$EUID" -ne '0' ]] && echo "Error:This script must be run as root!" && exit 1;

base=/etc/dnat
mkdir -p $base 2>/dev/null
conf=$base/conf
firstAfterBoot=1
lastConfig="/nftables_nat.sh"
lastConfigTmp="/nftables_nat.sh_tmp"

####
echo "正在安装依赖...."
yum install -y bind-utils nftables &> /dev/null
apt install -y dnsutils nftables &> /dev/null
echo "Completed：依赖安装完毕"
echo ""
####
ensureNftTables(){
    nft list table ip nat &> /dev/null
    if [ $? -ne 0 ]; then
        nft add table ip nat
    fi
    nft list chain ip nat prerouting &> /dev/null
    if [ $? -ne 0 ]; then
        nft add chain ip nat prerouting { type nat hook prerouting priority -100 \; }
    fi
    nft list chain ip nat postrouting &> /dev/null
    if [ $? -ne 0 ]; then
        nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
    fi
    nft list table ip filter &> /dev/null
    if [ $? -ne 0 ]; then
        nft add table ip filter
    fi
    nft list chain ip filter forward &> /dev/null
    if [ $? -ne 0 ]; then
        nft add chain ip filter forward { type filter hook forward priority 0 \; policy accept \; }
    fi
}

turnOnNat(){
    echo "1. 端口转发开启  【成功】"
    sed -n '/^net.ipv4.ip_forward=1/'p /etc/sysctl.conf | grep -q "net.ipv4.ip_forward=1"
    if [ $? -ne 0 ]; then
        echo -e "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && sysctl -p
    fi

    echo "2. 确保nftables nat表和链就绪  【成功】"
    ensureNftTables
}
turnOnNat

testVars(){
    local localport=$1
    local remotehost=$2
    local remoteport=$3
    echo "$localport"|[ -n "`sed -n '/^[0-9-][0-9-]*$/p'`" ] && echo $remoteport |[ -n "`sed -n '/^[0-9-][0-9-]*$/p'`" ]||{
       return 1;
    }
}

dnat(){
     [ "$#" = "3" ]&&{
        local localport=$1
        local remote=$2
        local remoteport=$3

        local nft_dport=${localport//-/:}
        local snat_dport=${remoteport//-/:}

        cat >> $lastConfigTmp <<EOF
nft add rule ip nat prerouting tcp dport $nft_dport dnat to $remote:$remoteport
nft add rule ip nat prerouting udp dport $nft_dport dnat to $remote:$remoteport
nft add rule ip nat postrouting ip daddr $remote tcp dport $snat_dport snat to $localIP
nft add rule ip nat postrouting ip daddr $remote udp dport $snat_dport snat to $localIP
EOF
    }
}

dnatIfNeed(){
  [ "$#" = "3" ]&&{
    local needNat=0
    if [ "$(echo  $2 |grep -E -o '([0-9]{1,3}[\.]){3}[0-9]{1,3}')" != "" ];then
        local remote=$2
    else
        local remote=$(host -t a  $2|grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}"|head -1)
    fi

    if [ "$remote" = "" ];then
            echo Warn:解析失败
          return 1;
     fi
  }||{
      echo "Error: host命令缺失或传递的参数数量有误"
      return 1;
  }
    echo $remote >$base/${1}IP
    dnat $1 $remote $3
}


echo "3. 开始监听域名解析变化"
echo ""
while true ;
do
localIP=$(ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 | grep -Ev '(^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.1[6-9]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.2[0-9]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^172\.3[0-1]{1}[0-9]{0,1}\.[0-9]{1,3}\.[0-9]{1,3}$)|(^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$)')
if [ "${localIP}" = "" ]; then
        localIP=$(ip -o -4 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1|head -n 1 )
fi
echo  "本机网卡IP [$localIP]"
cat > $lastConfigTmp <<EOF
nft flush chain ip nat prerouting
nft flush chain ip nat postrouting
EOF
arr1=(`cat $conf`)
for cell in ${arr1[@]}
do
    arr2=(`echo $cell|tr ":" " "|tr ">" " "`) 
    [ "${arr2[2]}" != "" -a "${arr2[3]}" = "" ]&& testVars ${arr2[0]}  ${arr2[1]} ${arr2[2]}&&{
        echo "转发规则： ${arr2[0]} => ${arr2[1]}:${arr2[2]}"
        dnatIfNeed ${arr2[0]} ${arr2[1]} ${arr2[2]}
    }
done

lastConfigTmpStr=`cat $lastConfigTmp`
lastConfigStr=`cat $lastConfig`
if [ "$firstAfterBoot" = "1" -o "$lastConfigTmpStr" != "$lastConfigStr" ];then
    echo '更新nftables规则[DOING]'
    source $lastConfigTmp
    cat $lastConfigTmp > $lastConfig
    echo '更新nftables规则[DONE]'
else
 echo "nftables规则未变更"
fi

firstAfterBoot=0
echo '' > $lastConfigTmp
sleep 60
done    
AAAA

cat > /lib/systemd/system/dnat.service <<\EOF
[Unit]
Description=动态设置nftables转发规则
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/root/
EnvironmentFile=
ExecStart=/bin/bash /usr/local/bin/dnat.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

ln -sf "$(readlink -f "$0")" /usr/local/bin/ipt
ln -sf "$(readlink -f "$0")" /usr/local/bin/kk
    systemctl daemon-reload
systemctl enable dnat > /dev/null 2>&1
service dnat stop > /dev/null 2>&1
service dnat start > /dev/null 2>&1
}


addDnat(){
    echo -e " ${CYAN}▶ 请选择转发模式：${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 单端口转发       ${YELLOW}(例: 80 -> 80)${PLAIN}"
    echo -e "  ${GREEN}2.${PLAIN} 一键范围转发     ${YELLOW}(10000 -> 65535)${PLAIN}"
    echo -e "  ${GREEN}3.${PLAIN} 自定义范围转发   ${YELLOW}(例: 10000 -> 20000)${PLAIN}"
    echo -ne " ${CYAN}请键入数字 [1-3]并回车:${PLAIN} "
    read f_mode

    local localport=
    local remoteport=
    local remotehost=

    if [ "$f_mode" = "2" ]; then
        localport="10000-65535"
        remoteport="10000-65535"
        echo -e " ${INFO} ${GREEN}已自动设定全范围：10000-65535${PLAIN}"
    elif [ "$f_mode" = "3" ]; then
        echo -ne " ${CYAN}请输入起始端口 ${YELLOW}(例: 10000)${PLAIN}: " 
        read start_p
        echo -ne " ${CYAN}请输入结束端口 ${YELLOW}(默认: 65535)${PLAIN}: " 
        read end_p
        [ -z "$end_p" ] && end_p=65535
        localport="${start_p}-${end_p}"
        remoteport="${start_p}-${end_p}"
    elif [ "$f_mode" = "1" ]; then
        echo -ne " ${CYAN}请输入本地监听端口:${PLAIN} " 
        read localport
        echo -ne " ${CYAN}请输入远程目标端口:${PLAIN} " 
        read remoteport
    else
        echo -e " ${ERROR} ${RED}选择无效，已取消。${PLAIN}"
        sleep 1
        return 1
    fi

    echo -ne " ${CYAN}请输入目标域名或IP地址:${PLAIN} " 
    read remotehost

    echo "$localport"|[ -n "`sed -n '/^[0-9-][0-9-]*$/p'`" ] && echo $remoteport |[ -n "`sed -n '/^[0-9-][0-9-]*$/p'`" ]||{
        echo -e " ${ERROR} ${RED}端口格式输入有误，必须是数字或范围！${PLAIN}"
        sleep 2
        return 1;
    }

    sed -i "s/^$localport.*/$localport>$remotehost:$remoteport/g" $conf
    [ "$(cat $conf|grep "$localport>$remotehost:$remoteport")" = "" ]&&{
            cat >> $conf <<LINE
$localport>$remotehost:$remoteport
LINE
    }
    
    echo ""
    echo -e " ${SUCCESS} ${GREEN}规则已添加: ${BOLD}${YELLOW}$localport ${CYAN}-> ${YELLOW}$remotehost:$remoteport${PLAIN}"
    echo -e " ${INFO} ${GREEN}服务配置重载中...${PLAIN}"
    setupService
    sleep 1
}

rmDnat(){
    echo -ne " ${CYAN}请输入要删除的本地端口号 ${YELLOW}(若为范围则输入 起始-结束)${PLAIN}: " 
    read localport
    sed -i "/^$localport>.*/d" $conf
    echo -e " ${SUCCESS} ${GREEN}已删除该规则！${PLAIN}"
    setupService
    sleep 1
}

modDnat(){
    echo -e " ${CYAN}---------- 当前配置的所有转发规则 ----------${PLAIN}"
    local rules=()
    local i=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        arr2=(`echo $line|tr ":" " "|tr ">" " "`)
        [ "${arr2[2]}" != "" -a "${arr2[3]}" = "" ] && {
            i=$((i+1))
            rules+=("$line")
            echo -e "  ${GREEN}$i.${PLAIN} ${BOLD}${YELLOW}${arr2[0]} ${CYAN}转发至 ${YELLOW}${arr2[1]}:${arr2[2]}${PLAIN}"
        }
    done < $conf
    echo -e " ${CYAN}--------------------------------------------${PLAIN}"

    if [ $i -eq 0 ]; then
        echo -e " ${YELLOW}目前没有任何转发规则。${PLAIN}"
        sleep 1
        return
    fi

    echo -ne " ${CYAN}请输入要修改的规则编号:${PLAIN} "
    read num

    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "$i" ]; then
        echo -e " ${ERROR} ${RED}无效的编号！${PLAIN}"
        sleep 1
        return 1
    fi

    local old_rule="${rules[$((num-1))]}"
    local old_arr=(`echo $old_rule|tr ":" " "|tr ">" " "`)
    local old_localport=${old_arr[0]}
    local old_remotehost=${old_arr[1]}
    local old_remoteport=${old_arr[2]}

    echo -e " ${INFO} 当前规则: ${YELLOW}${old_localport} -> ${old_remotehost}:${old_remoteport}${PLAIN}"

    echo -ne " ${CYAN}请输入新的本地监听端口 ${YELLOW}(留空保持不变)${PLAIN}: "
    read new_localport
    [ -z "$new_localport" ] && new_localport=$old_localport

    echo -ne " ${CYAN}请输入新的目标域名或IP ${YELLOW}(留空保持不变)${PLAIN}: "
    read new_remotehost
    [ -z "$new_remotehost" ] && new_remotehost=$old_remotehost

    echo -ne " ${CYAN}请输入新的远程目标端口 ${YELLOW}(留空保持不变)${PLAIN}: "
    read new_remoteport
    [ -z "$new_remoteport" ] && new_remoteport=$old_remoteport

    echo "$new_localport"|[ -n "`sed -n '/^[0-9-][0-9-]*$/p'`" ] && echo $new_remoteport |[ -n "`sed -n '/^[0-9-][0-9-]*$/p'`" ]||{
        echo -e " ${ERROR} ${RED}端口格式输入有误，必须是数字或范围！${PLAIN}"
        sleep 2
        return 1;
    }

    sed -i "/^${old_localport}>.*/d" $conf
    sed -i "s/^$new_localport.*/$new_localport>$new_remotehost:$new_remoteport/g" $conf
    [ "$(cat $conf|grep "$new_localport>$new_remotehost:$new_remoteport")" = "" ]&&{
        cat >> $conf <<LINE
$new_localport>$new_remotehost:$new_remoteport
LINE
    }

    echo ""
    echo -e " ${SUCCESS} ${GREEN}规则已修改: ${BOLD}${YELLOW}$new_localport ${CYAN}-> ${YELLOW}$new_remotehost:$new_remoteport${PLAIN}"
    echo -e " ${INFO} ${GREEN}服务配置重载中...${PLAIN}"
    setupService
    sleep 1
}

ensureNftTables(){
    nft list table ip nat &> /dev/null
    if [ $? -ne 0 ]; then
        nft add table ip nat
    fi
    nft list chain ip nat prerouting &> /dev/null
    if [ $? -ne 0 ]; then
        nft add chain ip nat prerouting { type nat hook prerouting priority -100\; }
    fi
    nft list chain ip nat postrouting &> /dev/null
    if [ $? -ne 0 ]; then
        nft add chain ip nat postrouting { type nat hook postrouting priority 100\; }
    fi
}

clearDnat(){
    echo -ne " ${WARN} ${RED}确定要清空所有转发规则吗？[y/N]: ${PLAIN}"
    read confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        > $conf
        ensureNftTables
        nft flush chain ip nat prerouting
        nft flush chain ip nat postrouting
        echo "" > /nftables_nat.sh_tmp
        echo -e " ${SUCCESS} ${GREEN}所有规则已彻底清空！${PLAIN}"
        setupService
    else
        echo -e " ${INFO} ${CYAN}已取消清理操作。${PLAIN}"
    fi
    sleep 1
}

lsDnat(){
    echo -e " ${CYAN}---------- 当前配置的所有转发规则 ----------${PLAIN}"
    arr1=(`cat $conf`)
    if [ ${#arr1[@]} -eq 0 ]; then
        echo -e " ${YELLOW}目前没有任何转发规则。${PLAIN}"
    else
        for cell in ${arr1[@]}  
        do
            arr2=(`echo $cell|tr ":" " "|tr ">" " "`)  
            [ "${arr2[2]}" != "" -a "${arr2[3]}" = "" ] && {
                echo -e "  ${GREEN}👉 ${BOLD}${YELLOW}${arr2[0]} ${CYAN}转发至 ${YELLOW}${arr2[1]}:${arr2[2]}${PLAIN}"
            }
        done
    fi
    echo -e " ${CYAN}--------------------------------------------${PLAIN}"
    echo -ne " ${INFO} ${GREEN}按回车键返回菜单...${PLAIN}"
    read
}

# ================= 主循环 =================
while true; do
    show_header
    echo -e " ${CYAN}请选择操作 (输入数字并回车):${PLAIN}"
    echo ""
    echo -e "  ${GREEN}1.${PLAIN} ➕ 增加转发规则"
    echo -e "  ${GREEN}2.${PLAIN} ✏️  修改转发规则"
    echo -e "  ${GREEN}3.${PLAIN} ➖ 删除转发规则"
    echo -e "  ${GREEN}4.${PLAIN} 📄 列出当前规则"
    echo -e "  ${RED}5.${PLAIN} 🗑️  一键清空所有规则"
    echo -e "  ${YELLOW}0.${PLAIN} 🚪 退出脚本"
    echo ""
    echo -ne " ${CYAN}请输入选项 [0-5]:${PLAIN} "
    read opt

    case $opt in
        1)
            echo ""
            addDnat
            ;;
        2)
            echo ""
            modDnat
            ;;
        3)
            echo ""
            rmDnat
            ;;
        4)
            echo ""
            lsDnat
            ;;
        5)
            echo ""
            clearDnat
            ;;
        0)
            echo -e " ${INFO} ${GREEN}感谢使用，再见！${PLAIN}"
            exit 0
            ;;
        *)
            echo -e " ${ERROR} ${RED}无效输入，请重新选择。${PLAIN}"
            sleep 1
            ;;
    esac
done
