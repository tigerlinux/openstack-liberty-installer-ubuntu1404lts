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
# First, we source our config file and verify that some important proccess are 
# already completed.
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

if [ -f /etc/openstack-control-script-config/db-installed ]
then
	echo ""
	echo "DB Proccess OK. Let's continue"
	echo ""
else
	echo ""
	echo "DB Proccess not completed. Aborting !"
	echo ""
	exit 0
fi

if [ -f /etc/openstack-control-script-config/keystone-installed ]
then
	echo ""
	echo "Keystone Proccess OK. Let's continue"
	echo ""
else
	echo ""
	echo "Keystone Proccess not completed. Aborting !"
	echo ""
	exit 0
fi

if [ -f /etc/openstack-control-script-config/trove-installed ]
then
	echo ""
	echo "This module was already completed. Exiting !"
	echo ""
	exit 0
fi


#
# We proceed to install all trove packages and dependencies, non-interactivelly
#

echo ""
echo "Installing TROVE Packages"

export DEBIAN_FRONTEND=noninteractive

DEBIAN_FRONTEND=noninteractive aptitude -y install python-trove python-troveclient python-glanceclient \
	trove-common trove-api trove-taskmanager trove-conductor

echo "Done"
echo ""


#
# Silently stops strove
#

stop trove-taskmanager >/dev/null 2>&1
stop trove-taskmanager >/dev/null 2>&1
stop trove-api >/dev/null 2>&1
stop trove-api >/dev/null 2>&1
stop trove-conductor >/dev/null 2>&1
stop trove-conductor >/dev/null 2>&1

rm -f /var/lib/trove/trovedb

source $keystone_admin_rc_file

#
# By using a python based "ini" config tool, we proceed to configure trove services
#

echo ""
echo "Configuring Trove"
echo ""

sync
sleep 5
sync

cat ./libs/trove/api-paste.ini > /etc/trove/api-paste.ini
cat ./libs/trove/trove.conf > /etc/trove/trove.conf
cat ./libs/trove/trove-taskmanager.conf > /etc/trove/trove-taskmanager.conf
cat ./libs/trove/trove-conductor.conf > /etc/trove/trove-conductor.conf
 
commonfile='
	/etc/trove/trove.conf
	/etc/trove/trove-taskmanager.conf
	/etc/trove/trove-conductor.conf
'
for myconffile in $commonfile
do
	echo "Configuring file $myconffile"
	sleep 3
	echo "#" >> $myconffile
 
	case $dbflavor in
	"mysql")
		crudini --set $myconffile database connection mysql+pymysql://$trovedbuser:$trovedbpass@$dbbackendhost:$mysqldbport/$trovedbname
		;;
	"postgres")
		crudini --set $myconffile database connection postgresql+psycopg2://$trovedbuser:$trovedbpass@$dbbackendhost:$psqldbport/$trovedbname
	;;
	esac
 
	crudini --set $myconffile DEFAULT log_dir /var/log/trove
	crudini --set $myconffile DEFAULT verbose False
	crudini --set $myconffile DEFAULT debug False
	crudini --set $myconffile DEFAULT control_exchange trove
	crudini --set $myconffile DEFAULT trove_auth_url http://$keystonehost:5000/v2.0
	crudini --set $myconffile DEFAULT nova_compute_url http://$novahost:8774/v2
	crudini --set $myconffile DEFAULT cinder_url http://$cinderhost:8776/v2
	crudini --set $myconffile DEFAULT swift_url http://$swifthost:8080/v1/AUTH_
	crudini --set $myconffile DEFAULT notifier_queue_hostname $messagebrokerhost
 
	case $brokerflavor in
	"qpid")
		crudini --set $myconffile DEFAULT rpc_backend trove.openstack.common.rpc.impl_qpid
		crudini --set $myconffile oslo_messaging_qpid qpid_hostname $messagebrokerhost
		crudini --set $myconffile oslo_messaging_qpid qpid_port 5672
		crudini --set $myconffile oslo_messaging_qpid qpid_username $brokeruser
		crudini --set $myconffile oslo_messaging_qpid qpid_password $brokerpass
		crudini --set $myconffile oslo_messaging_qpid qpid_heartbeat 60
		crudini --set $myconffile oslo_messaging_qpid qpid_protocol tcp
		crudini --set $myconffile oslo_messaging_qpid qpid_tcp_nodelay True
		;;
	"rabbitmq")
		crudini --set $myconffile DEFAULT rpc_backend trove.openstack.common.rpc.impl_kombu
		crudini --set $myconffile oslo_messaging_rabbit rabbit_host $messagebrokerhost
		crudini --set $myconffile oslo_messaging_rabbit rabbit_password $brokerpass
		crudini --set $myconffile oslo_messaging_rabbit rabbit_userid $brokeruser
		crudini --set $myconffile oslo_messaging_rabbit rabbit_port 5672
		crudini --set $myconffile oslo_messaging_rabbit rabbit_use_ssl false
		crudini --set $myconffile oslo_messaging_rabbit rabbit_virtual_host $brokervhost
		crudini --set $myconffile oslo_messaging_rabbit rabbit_max_retries 0
		crudini --set $myconffile oslo_messaging_rabbit rabbit_retry_interval 1
		crudini --set $myconffile oslo_messaging_rabbit rabbit_ha_queues false
	;;
	esac
done
 
 
crudini --set /etc/trove/trove-taskmanager.conf DEFAULT nova_proxy_admin_user $keystoneadminuser
crudini --set /etc/trove/trove-taskmanager.conf DEFAULT nova_proxy_admin_pass $keystoneadminpass
crudini --set /etc/trove/trove-taskmanager.conf DEFAULT nova_proxy_admin_tenant_name $keystoneadmintenant

#
# We set our default datastore by using our database flavor selected into our main config file
#
 
case $dbflavor in
"mysql")
	crudini --set /etc/trove/trove.conf DEFAULT default_datastore mysql
	;;
"postgres")
	crudini --set /etc/trove/trove.conf DEFAULT default_datastore postgresql
	;;
esac

crudini --set /etc/trove/trove.conf DEFAULT add_addresses True
crudini --set /etc/trove/trove.conf DEFAULT network_label_regex "^NETWORK_LABEL$"
crudini --set /etc/trove/trove.conf DEFAULT api_paste_config /etc/trove/api-paste.ini
crudini --set /etc/trove/trove.conf DEFAULT bind_host 0.0.0.0
crudini --set /etc/trove/trove.conf DEFAULT bind_port 8779
crudini --set /etc/trove/trove.conf DEFAULT taskmanager_manager trove.taskmanager.manager.Manager
 
troveworkers=`grep processor.\*: /proc/cpuinfo |wc -l`
 
crudini --set /etc/trove/trove.conf DEFAULT trove_api_workers $troveworkers
 
crudini --set /etc/trove/trove.conf keystone_authtoken signing_dir /var/cache/trove
crudini --set /etc/trove/trove.conf keystone_authtoken auth_uri http://$keystonehost:5000
crudini --set /etc/trove/trove.conf keystone_authtoken auth_url http://$keystonehost:35357
crudini --set /etc/trove/trove.conf keystone_authtoken auth_plugin password
crudini --set /etc/trove/trove.conf keystone_authtoken project_domain_id $keystonedomain
crudini --set /etc/trove/trove.conf keystone_authtoken user_domain_id $keystonedomain
crudini --set /etc/trove/trove.conf keystone_authtoken project_name $keystoneservicestenant
crudini --set /etc/trove/trove.conf keystone_authtoken username $troveuser
crudini --set /etc/trove/trove.conf keystone_authtoken password $trovepass


mkdir -p /var/cache/trove
chown -R trove.trove /var/cache/trove
chown trove.trove /etc/trove/*
chmod 700 /var/cache/trove
chmod 700 /var/log/trove

touch /var/log/trove/trove-manage.log
chown trove.trove /var/log/trove/*

echo ""
echo "Trove Configured"
echo ""

#
# We provision/update Trove database
#

echo ""
echo "Provisioning Trove DB"
echo ""

su -s /bin/sh -c "trove-manage db_sync" trove

#
# And we create the datastore
#

case $dbflavor in
"mysql")
	echo ""
	echo "Creating Trove MYSQL Datastore"
	echo ""
	su -s /bin/sh -c "trove-manage datastore_update mysql ''" trove
	;;
"postgres")
	echo ""
	echo "Creating Trove POSTGRESQL Datastore"
	echo ""
	su -s /bin/sh -c "trove-manage datastore_update postgresql ''" trove
	;;
esac

echo ""
echo "Done"
echo ""

#
# Here we apply IPTABLES rules and start/enable trove services
#

echo ""
echo "Applying IPTABLES rules"

iptables -A INPUT -p tcp -m multiport --dports 8779 -j ACCEPT
/etc/init.d/iptables-persistent save

echo "Done"

echo ""
echo "Cleaning UP App logs"

for mylog in `ls /var/log/trove/*.log`; do echo "" > $mylog;done

echo "Done"
echo ""

echo ""
echo "Starting Services"
echo ""

start trove-api
start trove-taskmanager
start trove-conductor

#
# And finally, we do a little test to ensure our trove packages are installed. If we
# fail this test, we stop the installer from this point.
#

testtrove=`dpkg -l trove-api 2>/dev/null|tail -n 1|grep -ci ^ii`
if [ $testtrove == "0" ]
then
        echo ""
        echo "TROVE Installation Failed. Aborting !"
        echo ""
        exit 0
else
        date > /etc/openstack-control-script-config/trove-installed
        date > /etc/openstack-control-script-config/trove
fi

echo ""
echo "Trove Installed and Configured"
echo ""

