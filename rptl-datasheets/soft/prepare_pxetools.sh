#!/bin/bash

set -e

sudo apt install -y python3 python3-pip ipcalc
sudo pip3 install tabulate

# Get network info
NAMESERVER=$(cat /etc/resolv.conf | grep nameserver | head -n 1 | cut -d " " -f2)
GATEWAY=$(ip -4 route | grep default | head -n 1 | cut -d " " -f3)
IP=$(ifconfig eth0 | grep "inet addr" | cut -d " " -f 12 | cut -d ":" -f 2)
BRD=$(ifconfig eth0 | grep "inet addr" | cut -d " " -f 14 | cut -d ":" -f 2)
NETMASK=$(ifconfig eth0 | grep "inet addr" | cut -d " " -f 16 | cut -d ":" -f 2)

echo "IP: $IP"
echo "Netmask: $NETMASK"
echo "Broadcast: $BRD"
echo "Nameserver: $NAMESERVER"
echo "Gateway: $GATEWAY"

echo "Setting static IP using above information"

cat << EOF | sudo tee /etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
	address $IP
	netmask $NETMASK
	gateway $GATEWAY
EOF

sudo systemctl stop dhcpcd
sudo systemctl disable dhcpcd
sudo systemctl restart networking

# In case it is already set
sudo chattr -i /etc/resolv.conf

echo "Setting nameserver"
cat << EOF | sudo tee /etc/resolv.conf
nameserver $NAMESERVER
EOF

# Prevent DNSMasq from changing
sudo chattr +i /etc/resolv.conf

sudo apt install -y nfs-kernel-server dnsmasq iptables-persistent unzip nmap kpartx rsync

sudo mkdir -p /nfs
sudo mkdir -p /tftpboot
sudo cp -r /boot /tftpboot/base
sudo cp /boot/bootcode.bin /tftpboot
sudo chmod -R 777 /tftpboot

echo "Writing dnsmasq.conf"
cat << EOF | sudo tee /etc/dnsmasq.conf
port=0
dhcp-range=$BRD,proxy
bind-interfaces
log-dhcp
enable-tftp
log-facility=/var/log/dnsmasq
tftp-root=/tftpboot
pxe-service=0,"Raspberry Pi Boot"
EOF

# Flush any rules that might exist
sudo iptables -t raw --flush

# Create the DHCP_clients chain in the 'raw' table
sudo iptables -t raw -N DHCP_clients || true

# Incoming DHCP, pass to chain processing DHCP
sudo iptables -t raw -A PREROUTING -p udp --dport 67 -j DHCP_clients

# Deny clients not in chain not listed above
sudo iptables -t raw -A DHCP_clients -j DROP

sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Start services
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq
sudo systemctl enable rpcbind
sudo systemctl restart rpcbind
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server

echo "Getting latest Raspberry Pi OS lite image to use as NFS root"
# Get latest Raspberry Pi OS lite image
sudo mkdir -p /nfs/bases
cd /nfs/bases
sudo wget -O raspios_latest.zip https://downloads.raspberrypi.org/raspios_lite_armhf_latest
sudo unzip raspios_latest.zip
sudo rm raspios_latest.zip

sudo wget  -O /usr/local/sbin/pxetools https://datasheets.raspberrypi.org/soft/pxetools.py
sudo chmod +x /usr/local/sbin/pxetools

echo "Now run sudo pxetools --add \$serial"
