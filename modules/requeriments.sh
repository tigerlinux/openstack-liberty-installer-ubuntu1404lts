#!/bin/bash
#
# Unattended/SemiAutomatted OpenStack Installer
# Reynaldo R. Martinez P.
# E-Mail: TigerLinux@Gmail.com
# OpenStack LIBERTY for Ubuntu 14.04lts
#
#

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

#
# First, we source our config file
#

if [ -f ./configs/main-config.rc ]
then
	source ./configs/main-config.rc
	mkdir -p /etc/openstack-control-script-config
else
	echo "Can't access my config file. Aborting !"
	echo ""
	exit 0
fi

#
# Some pre-cleanup first !. Just in order to avoid "Oppssess"
#

rm -rf /tmp/keystone-signing-*
rm -rf /tmp/cd_gen_*

#
# Then we begin some verifications
#

export DEBIAN_FRONTEND=noninteractive

DEBIAN_FRONTEND=noninteractive apt-get -y install aptitude

osreposinstalled=`aptitude search python-openstackclient|grep python-openstackclient|head -n1|wc -l`
amiroot=` whoami|grep root|wc -l`
amiubuntu1404=`cat /etc/lsb-release|grep DISTRIB_DESCRIPTION|grep -i ubuntu.\*14.\*LTS|head -n1|wc -l`
internalbridgepresent=`ovs-vsctl show|grep -i -c bridge.\*$integration_bridge`
kernel64installed=`uname -p|grep x86_64|head -n1|wc -l`

echo ""
echo "Starting Verifications"
echo ""

if [ $amiubuntu1404 == "1" ]
then
	echo ""
	echo "UBUNTU 14.04 LTS O/S Verified OK"
	echo ""
else
	echo ""
	echo "We could not verify an UBUNTU 14.04 LTS O/S here. Aborting !"
	echo ""
	exit 0
fi

if [ $amiroot == "1" ]
then
	echo ""
	echo "We are root. That's OK"
	echo ""
else
	echo ""
	echo "Apparently, we are not running as root. Aborting !"
	echo ""
	exit 0
fi

if [ $kernel64installed == "1" ]
then
	echo ""
	echo "Kernel x86_64 (amd64) detected. Thats OK"
	echo ""
else
	echo ""
	echo "Apparently, we are not running inside a x86_64 Kernel. Thats NOT Ok. Aborting !"
	echo ""
	exit 0
fi


echo ""
echo "Let's continue"
echo ""

searchtestceilometer=`aptitude search ceilometer-api|grep -ci "ceilometer-api"`

if [ $osreposinstalled == "1" ]
then
	echo ""
	echo "OpenStack LIBERTY Repository apparently installed OK"
else
	echo ""
	echo "OpenStack LIBERTY Repository apparently NOT installed or NOT Enabled. Aborting !"
	echo ""
	exit 0
fi

if [ $searchtestceilometer == "1" ]
then
	echo ""
	echo "Second OpenStack REPO verification OK"
	echo ""
else
	echo ""
	echo "Second OpenStack REPO verification FAILED. Aborting !"
	echo ""
	exit 0
fi

if [ $internalbridgepresent == "1" ]
then
	echo ""
	echo "Integration Bridge Present"
	echo ""
else
	echo ""
	echo "Integration Bridge NOT Present. Aborting !"
	echo ""
	exit 0
fi

echo "Installing initial packages"
echo ""

#
# We proceed to install some initial packages, some of then non-interactivelly
#

apt-get -y update
apt-get -y install crudini python-iniparse debconf-utils

echo "libguestfs0 libguestfs/update-appliance boolean false" > /tmp/libguest-seed.txt
debconf-set-selections /tmp/libguest-seed.txt

DEBIAN_FRONTEND=noninteractive aptitude -y install pm-utils saidar sysstat iotop ethtool iputils-arping libsysfs2 btrfs-tools \
	cryptsetup cryptsetup-bin febootstrap jfsutils libconfig8-dev \
	libcryptsetup4 libguestfs0 libhivex0 libreadline5 reiserfsprogs scrub xfsprogs \
	zerofree zfs-fuse virt-top curl nmon fuseiso9660 libiso9660-8 genisoimage sudo sysfsutils \
	glusterfs-client glusterfs-common nfs-client nfs-common libguestfs-tools

rm -r /tmp/libguest-seed.txt

#
# Then we proceed to configure Libvirt and iptables, and also to verify proper installation
# of libvirt. If that fails, we stop here !
#

if [ -f /etc/openstack-control-script-config/libvirt-installed ]
then
	echo ""
	echo "Pre-requirements already installed"
	echo ""
else
	echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" > /tmp/iptables-seed.txt
	echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" >> /tmp/iptables-seed.txt
	debconf-set-selections /tmp/iptables-seed.txt
	DEBIAN_FRONTEND=noninteractive aptitude -y install iptables iptables-persistent
	/etc/init.d/iptables-persistent flush
	/etc/init.d/iptables-persistent save
	update-rc.d iptables-persistent enable
	/etc/init.d/iptables-persistent save
	rm -f /tmp/iptables-seed.txt
	DEBIAN_FRONTEND=noninteractive aptitude -y install qemu kvm qemu-kvm libvirt-bin libvirt-doc
	rm -f /etc/libvirt/qemu/networks/default.xml
	rm -f /etc/libvirt/qemu/networks/autostart/default.xml
	/etc/init.d/libvirt-bin stop
	update-rc.d libvirt-bin enable
	ifconfig virbr0 down
	DEBIAN_FRONTEND=noninteractive aptitude -y install dnsmasq dnsmasq-utils
	/etc/init.d/dnsmasq stop
	update-rc.d dnsmasq disable
	killall -9 dnsmasq
	sed -r -i 's/ENABLED\=1/ENABLED\=0/' /etc/default/dnsmasq
	/etc/init.d/iptables-persistent flush
	iptables -A INPUT -p tcp -m multiport --dports 22 -j ACCEPT
	/etc/init.d/iptables-persistent save
	/etc/init.d/libvirt-bin start

	sed -i.ori 's/#listen_tls = 0/listen_tls = 0/g' /etc/libvirt/libvirtd.conf
	sed -i 's/#listen_tcp = 1/listen_tcp = 1/g' /etc/libvirt/libvirtd.conf
	sed -i 's/#auth_tcp = "sasl"/auth_tcp = "none"/g' /etc/libvirt/libvirtd.conf
	sed -i.ori 's/libvirtd_opts="-d"/libvirtd_opts="-d -l"/g' /etc/default/libvirt-bin

	/etc/init.d/libvirt-bin restart

	iptables -A INPUT -p tcp -m multiport --dports 16509 -j ACCEPT
	/etc/init.d/iptables-persistent save

	apt-get -y install apparmor-utils
	aa-disable /etc/apparmor.d/usr.sbin.libvirtd
	/etc/init.d/libvirt-bin restart

fi

#
# We configure ksm
#

cp ./libs/ksm.sh /etc/init.d/ksm
chmod 755 /etc/init.d/ksm
/etc/init.d/ksm restart
/etc/init.d/ksm status
update-rc.d ksm enable

testlibvirt=`dpkg -l libvirt-bin 2>/dev/null|tail -n 1|grep -ci ^ii`

if [ $testlibvirt == "1" ]
then
	echo ""
	echo "Libvirt correctly installed"
	date > /etc/openstack-control-script-config/libvirt-installed
	echo ""
else
	echo ""
	echo "Libvirt installation FAILED. Aborting !"
	exit 0
fi

