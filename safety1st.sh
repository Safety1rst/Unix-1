#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
if ! [[ -e /etc/debian_version ]]; then
	echo For DEBIAN and UBUNTU only.
	exit;fi
if [[ `lsb_release -si` = Debian ]];then
	sed -i 's/jessie/stretch/g' /etc/apt/sources.list
else sed -i 's/xenial/bionic/g' /etc/apt/sources.list;fi
OPT='-o Acquire::Check-Valid-Until=false -yq -o DPkg::Options::=--force-confdef -o DPkg::Options::=--force-confnew --allow-unauthenticated'
apt-get update
yes | apt $OPT dist-upgrade
apt-get install openvpn openssl squid -y
PORT="1194"
IP=$(wget -qO- ipv4.icanhazip.com)
PROTOCOL="TCP"
CIPHER="AES-128-CBC"
DH_KEY_SIZE="2048"
RSA_KEY_SIZE="2048"
CLIENT="Client"
FNAME=client-${IP##*.}.ovpn
newclient() {

	cp /etc/openvpn/client-template.txt ~/$FNAME
	{
		echo "<ca>"
		cat "/etc/openvpn/easy-rsa/pki/ca.crt"
		echo "</ca>"

		echo "<cert>"
		cat "/etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt"
		echo "</cert>"

		echo "<key>"
		cat "/etc/openvpn/easy-rsa/pki/private/$CLIENT.key"
		echo "</key>"
		echo "key-direction 1"

		echo "<tls-auth>"
		cat "/etc/openvpn/tls-auth.key"
		echo "</tls-auth>"
	} >> ~/$FNAME
}
	# Reset IPTABLES
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
iptables -t nat -A POSTROUTING -o $(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1) -j MASQUERADE
iptables -I FORWARD -j ACCEPT
iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" > /sbin/iptab
	chmod a+x /sbin/iptab;iptab
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
sysctl -p
systemctl daemon-reload
systemctl enable iptab
cd /etc/openvpn
if ! [ -d easy-rsa/EasyRSA-3.0.4 ];then
wget -qO- https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.4/EasyRSA-3.0.4.tgz | tar xz
mv EasyRSA-3.0.4 easy-rsa; fi
if ! [ -f /etc/openvpn/server.conf ];then
cd /etc/openvpn/easy-rsa/ || return
SERVER_CN="cn_$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)"
SERVER_NAME="server_$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)"
echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE
set_var EASYRSA_REQ_CN $SERVER_CN
set_var EASYRSA_CRL_DAYS 3650" > vars
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass
	openssl dhparam -out dh.pem $DH_KEY_SIZE
	./easyrsa build-server-full $SERVER_NAME nopass
	./easyrsa build-client-full $CLIENT nopass
	./easyrsa gen-crl
	openvpn --genkey --secret /etc/openvpn/tls-auth.key
	cp pki/ca.crt pki/private/ca.key dh.pem pki/issued/$SERVER_NAME.crt pki/private/$SERVER_NAME.key /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
	chmod a+x /etc/openvpn/crl.pem
else SERVER_NAME=`ls /etc/openvpn/server*.key | grep -oE 'server\w[0-9a-Z]+'`; fi
	# Generate server.conf
	echo 'port 1194
proto tcp
dev tun
crl-verify crl.pem
ca ca.crt
cert '$SERVER_NAME'.crt
key '$SERVER_NAME'.key
tls-auth tls-auth.key 0
dh dh.pem
topology subnet
server 10.10.0.0 255.255.255.0
push "dhcp-option DNS 67.207.67.2"
push "dhcp-option DNS 67.207.67.3"
push "redirect-gateway def1 bypass-dhcp"
cipher AES-128-CBC
ncp-ciphers AES-128-GCM:AES-128-CBC
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
status clients.log
duplicate-cn
tcp-nodelay
reneg-sec 0' > /etc/openvpn/server.conf
echo "client
dev tun
proto tcp
remote-cert-tls server
remote 127.0.0.1 $PORT
http-proxy $IP 993
http-proxy-option VERSION 1.1
http-proxy-option CUSTOM-HEADER Host i.line.me
setenv opt block-outside-dns
cipher AES-128-CBC
auth-nocache" > /etc/openvpn/client-template.txt
sq=$([ -d /etc/squid ] && echo squid || echo squid3)
mv /etc/$sq/squid.conf /etc/$sq/squid.confx
echo 'http_access allow all
via off
http_port 993
visible_hostname udp.team' > /etc/$sq/squid.conf
systemctl restart {$sq,openvpn@server,iptab}
newclient
clear
wget -qO- "https://raw.githubusercontent.com/X-DCB/Unix/master/banner" | bash
echo "Finished!"
echo "Your client config is available at /root/$FNAME.ovpn"