#!/bin/bash
# Check Root Acecss
if [[ "$EUID" -ne 0 ]]; then
	echo "Sorry, you need to run this as root"
	exit 1
fi
# Check if Debian Distro
if ! [[ -e /etc/debian_version ]]; then
	echo For DEBIAN and UBUNTU only.
	exit 1;fi
export DEBIAN_FRONTEND=noninteractive
# Upgrade to Ubuntu 18.04/Debian 9
. /etc/os-release
if [[ "$VERSION_CODENAME" = jessie ]];then
	sed -i 's/jessie/stretch/g' /etc/apt/sources.list; fi
if [[ "$VERSION_CODENAME" = xenial ]];then
	sed -i 's/xenial/bionic/g' /etc/apt/sources.list;fi
OPT='-o Acquire::Check-Valid-Until=false -yq -o DPkg::Options::=--force-confdef -o DPkg::Options::=--force-confnew --allow-unauthenticated'
apt-get update
yes | apt $OPT dist-upgrade
# Installation
apt-get install openvpn openssl squid ca-certificates -y
cd /etc/openvpn
if ! [ -d easyrsa ];then
wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz -qO- | tar xz
mv EasyRSA* easyrsa || return
cd easyrsa
[ -f 'cn_name' ] || echo "SERVER_CN=cn_$(tr -dc \'a-zA-Z0-9\' < /dev/urandom | fold -w 16 | head -n 1)
SERVER_NAME=server_$(tr -dc \'a-zA-Z0-9\' < /dev/urandom | fold -w 16 | head -n 1)" > cn_name
. cn_name
RSA_KEY_SIZE=2048
DH_KEY_SIZE=2048
CIPHER="AES-128-CBC"
echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE
set_var EASYRSA_REQ_CN $SERVER_CN" > vars
./easyrsa init-pki
touch pki/.rnd
./easyrsa --batch build-ca nopass
openssl dhparam -out dh.pem $DH_KEY_SIZE
./easyrsa build-server-full $SERVER_NAME nopass
./easyrsa build-client-full Client nopass
EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
openvpn --genkey --secret tls-auth.key
cp pki/ca.crt pki/private/ca.key dh.pem pki/issued/$SERVER_NAME.crt pki/private/$SERVER_NAME.key pki/crl.pem pki/issued/Client.crt pki/private/Client.key tls-auth.key /etc/openvpn
cd /etc/openvpn
chmod a+x crl.pem
# IPTables
echo "#!/bin/sh
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -I FORWARD -j ACCEPT
iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
sysctl -w net.ipv4.ip_forward=1" > /sbin/iptab
chmod a+x /sbin/iptab && iptab
# Packet Filtering Service
echo "[Unit]
Description=Packet Filtering Framework
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target
[Service]
Type=oneshot
ExecStart=/sbin/iptab
ExecReload=/sbin/iptab
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/iptab.service
sed -i '/net.ipv4.ip_forward/{s/#//g}' /etc/sysctl.conf
# Reinitialize
sysctl -p
systemctl daemon-reload
systemctl enable iptab
# Squid
sq=$([ -d /etc/squid ] && echo squid || echo squid3)
mv /etc/$sq/squid.conf /etc/$sq/squid.confx
echo 'http_access allow all
via off
http_port 0.0.0.0:993
visible_hostname udp.team' > /etc/$sq/squid.conf
else
. easyrsa/cn_name; fi
# Server Config
cat > server.conf << CONF
port 1194
proto tcp
dev tun

keepalive 10 60
topology subnet
server 10.10.10.0 255.255.255.224
push "dhcp-option DNS 67.207.67.2"
push "dhcp-option DNS 67.207.67.3"
push "redirect-gateway def1 bypass-dhcp"
crl-verify crl.pem
ca ca.crt
cert $SERVER_NAME.crt
key $SERVER_NAME.key
tls-auth tls-auth.key 0
dh dh.pem
cipher $CIPHER
auth SHA1
ncp-ciphers AES-128-GCM:AES-128-CBC
tls-server
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
status clients.log
duplicate-cn
tcp-nodelay
reneg-sec 0
CONF
# CLient Config
cat > ~/client.ovpn << OVPN
client
dev tun
proto tcp
remote-cert-tls server
remote 127.0.0.1 1194
http-proxy $(wget -qO- ipv4.icanhazip.com) 993
http-proxy-option VERSION 1.1
http-proxy-option CUSTOM-HEADER Host weixin.qq.cn
setenv opt block-outside-dns
cipher $CIPHER
auth SHA1
key-direction 1
auth-nocache

<ca>
`cat ca.crt`
</ca>
<cert>
`cat Client.crt`
</cert>
<key>
`cat Client.key`
</key>
<tls-auth>
`cat tls-auth.key`
</tls-auth>
OVPN
# Restart services
systemctl restart {$sq,openvpn@server,iptab}
clear
wget -qO- "https://raw.githubusercontent.com/X-DCB/Unix/master/banner" | bash
echo -ne "\nYour client config is saved in /root/client.ovpn.\nFinished! \n"

exit 0