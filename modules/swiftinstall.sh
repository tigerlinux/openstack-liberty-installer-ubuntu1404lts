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

if [ -f /etc/openstack-control-script-config/swift-installed ]
then
	echo ""
	echo "This module was already completed. Exiting !"
	echo ""
	exit 0
fi

#
# We perform some validations related to the filesystem device and mount point. If those
# validations fail, we abort from here !.
#

echo ""
echo "Preparing FS Resources"
echo ""

if [ ! -d "/srv/node" ]
then
	rm -f /etc/openstack-control-script-config/swift
	echo ""
	echo "WARNING !. the main mount point is not here. Aborting swift installation"
	echo "OpenStack installation will continue, but without swift"
	echo "Sleeping 10 seconds"
	echo ""
	sleep 10
	exit 0
fi

checkdevice=`mount|awk '{print $3}'|grep -c ^/srv/node/$swiftdevice$`

case $checkdevice in
1)
	echo ""
	echo "Mount Point /srv/node/$swiftdevice OK"
	echo "Let's continue"
	echo ""
	;;
0)
	rm -f /etc/openstack-control-script-config/swift
	rm -f /etc/openstack-control-script-config/swift-installed
	echo ""
	echo "WARNING !. the main swift device is not here. Aborting swift installation"
	echo "OpenStack installation will continue, but without swift"
	echo "Sleeping 10 seconds"
	echo ""
	sleep 10
	echo ""
	exit 0
	;;
esac

if [ $cleanupdeviceatinstall == "yes" ]
then
	rm -rf /srv/node/$swiftdevice/accounts
	rm -rf /srv/node/$swiftdevice/containers
	rm -rf /srv/node/$swiftdevice/objects
	rm -rf /srv/node/$swiftdevice/tmp
fi

#
# Validations done OK, then we proceed to install packages, non-interactivelly
#

echo ""
echo "Installing SWIFT Packages"

export DEBIAN_FRONTEND=noninteractive

DEBIAN_FRONTEND=noninteractive aptitude -y install swift swift-account swift-container swift-doc \
	swift-object swift-proxy memcached python-swift \
	python-swiftclient python-keystoneclient python-keystonemiddleware


#
# We silently stops all swift services
#

stop swift-account >/dev/null 2>&1
stop swift-account-auditor >/dev/null 2>&1
stop swift-account-reaper >/dev/null 2>&1
stop swift-account-replicator >/dev/null 2>&1

stop swift-container >/dev/null 2>&1
stop swift-container-auditor >/dev/null 2>&1
stop swift-container-replicator >/dev/null 2>&1
stop swift-container-updater >/dev/null 2>&1

stop swift-object >/dev/null 2>&1
stop swift-object-auditor >/dev/null 2>&1
stop swift-object-replicator >/dev/null 2>&1
stop swift-object-updater >/dev/null 2>&1

killall -9 -u swift >/dev/null 2>&1
killall -9 -u swift >/dev/null 2>&1

echo "Done"
echo ""

source $keystone_admin_rc_file

#
# We apply IPTABLES rules
#

iptables -A INPUT -p tcp -m multiport --dports 6000,6001,6002,873 -j ACCEPT
/etc/init.d/iptables-persistent save

#
# Fixing permissions
#

chown -R swift:swift /srv/node/

#
# By using a python based "ini" config tool, we proceed to configure swift services
#

echo ""
echo "Configuring Swift"
echo ""

#
# First, as we obtained the configurations from the main git repository, we ensure
# all of those configs are properlly copied to the swift directory
#

cat ./libs/swift/account-server.conf > /etc/swift/account-server.conf
cat ./libs/swift/container-reconciler.conf > /etc/swift/container-reconciler.conf
cat ./libs/swift/container-server.conf > /etc/swift/container-server.conf
cat ./libs/swift/object-expirer.conf > /etc/swift/object-expirer.conf
cat ./libs/swift/object-server.conf > /etc/swift/object-server.conf
cat ./libs/swift/proxy-server.conf > /etc/swift/proxy-server.conf
cat ./libs/swift/swift.conf > /etc/swift/swift.conf

echo "#" >> /etc/swift/swift.conf

chown -R swift:swift /etc/swift

mkdir -p /var/lib/keystone-signing-swift
chown swift:swift /var/lib/keystone-signing-swift

crudini --set /etc/swift/swift.conf swift-hash swift_hash_path_suffix $(openssl rand -hex 10)
crudini --set /etc/swift/swift.conf swift-hash swift_hash_path_prefix $(openssl rand -hex 10)
crudini --set /etc/swift/swift.conf "storage-policy:0" name Policy-0
crudini --set /etc/swift/swift.conf "storage-policy:0" default yes
 
#swiftworkers=`grep processor.\*: /proc/cpuinfo |wc -l`
swiftworkers="auto"

mkdir -p "/var/cache/swift"
chmod 0700 /var/cache/swift
chown -R swift:swift /var/cache/swift
# chown -R root:swift /var/cache/swift
 
crudini --set /etc/swift/object-server.conf DEFAULT bind_ip $swifthost
crudini --set /etc/swift/object-server.conf DEFAULT workers $swiftworkers
crudini --set /etc/swift/object-server.conf DEFAULT swift_dir "/etc/swift"
crudini --set /etc/swift/object-server.conf DEFAULT devices "/srv/node"
crudini --set /etc/swift/object-server.conf DEFAULT bind_port 6000
# crudini --set /etc/swift/object-server.conf DEFAULT mount_check false
crudini --set /etc/swift/object-server.conf DEFAULT mount_check true
crudini --set /etc/swift/object-server.conf DEFAULT user swift
crudini --set /etc/swift/object-server.conf "pipeline:main" pipeline "healthcheck recon object-server"
crudini --set /etc/swift/object-server.conf "filter:recon" use "egg:swift#recon"
crudini --set /etc/swift/object-server.conf "filter:recon" recon_cache_path "/var/cache/swift"
crudini --set /etc/swift/object-server.conf "filter:recon" recon_lock_path "/var/lock"

crudini --set /etc/swift/account-server.conf DEFAULT bind_ip $swifthost
crudini --set /etc/swift/account-server.conf DEFAULT workers $swiftworkers
crudini --set /etc/swift/account-server.conf DEFAULT swift_dir "/etc/swift"
crudini --set /etc/swift/account-server.conf DEFAULT devices "/srv/node"
crudini --set /etc/swift/account-server.conf DEFAULT bind_port 6002
#crudini --set /etc/swift/account-server.conf DEFAULT mount_check false
crudini --set /etc/swift/account-server.conf DEFAULT mount_check true
crudini --set /etc/swift/account-server.conf DEFAULT user swift
crudini --set /etc/swift/account-server.conf "pipeline:main" pipeline "healthcheck recon account-server"
crudini --set /etc/swift/account-server.conf "filter:recon" use "egg:swift#recon"
crudini --set /etc/swift/account-server.conf "filter:recon" recon_cache_path "/var/cache/swift"

crudini --set /etc/swift/container-server.conf DEFAULT bind_ip $swifthost
crudini --set /etc/swift/container-server.conf DEFAULT workers $swiftworkers
crudini --set /etc/swift/container-server.conf DEFAULT swift_dir "/etc/swift"
crudini --set /etc/swift/container-server.conf DEFAULT devices "/srv/node"
crudini --set /etc/swift/container-server.conf DEFAULT bind_port 6001
#crudini --set /etc/swift/container-server.conf DEFAULT mount_check false
crudini --set /etc/swift/container-server.conf DEFAULT mount_check true
crudini --set /etc/swift/container-server.conf DEFAULT user swift
crudini --set /etc/swift/container-server.conf "pipeline:main" pipeline "healthcheck recon container-server"
crudini --set /etc/swift/container-server.conf "filter:recon" "egg:swift#recon"
crudini --set /etc/swift/container-server.conf "filter:recon" recon_cache_path "/var/cache/swift"

#
# Then we proceed to configure the proxy service
#

crudini --set /etc/swift/proxy-server.conf DEFAULT bind_port 8080
crudini --set /etc/swift/proxy-server.conf DEFAULT user swift
crudini --set /etc/swift/proxy-server.conf DEFAULT swift_dir /etc/swift
 crudini --set /etc/swift/proxy-server.conf DEFAULT workers $swiftworkers
# crudini --set /etc/swift/proxy-server.conf "pipeline:main" pipeline "catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo proxy-logging proxy-server"
crudini --set /etc/swift/proxy-server.conf "pipeline:main" pipeline "catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo versioned_writes proxy-logging proxy-server"
crudini --set /etc/swift/proxy-server.conf "app:proxy-server" use "egg:swift#proxy"
crudini --set /etc/swift/proxy-server.conf "app:proxy-server" allow_account_management true
crudini --set /etc/swift/proxy-server.conf "app:proxy-server" account_autocreate true
crudini --set /etc/swift/proxy-server.conf "filter:keystoneauth" use "egg:swift#keystoneauth"
# crudini --set /etc/swift/proxy-server.conf "filter:keystoneauth" operator_roles "$keystonememberrole,$keystoneadmintenant,$keystoneuserrole,swiftoperator"
crudini --set /etc/swift/proxy-server.conf "filter:keystoneauth" operator_roles "$keystoneadmintenant,$keystoneuserrole"
crudini --set /etc/swift/proxy-server.conf "filter:keystoneauth" reseller_admin_role $keystonereselleradminrole
crudini --set /etc/swift/proxy-server.conf "filter:keystoneauth" allow_overrides true
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" paste.filter_factory "keystonemiddleware.auth_token:filter_factory"
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" delay_auth_decision true

# Very very very deprecated !!
#crudini --set /etc/swift/proxy-server.conf "filter:authtoken" admin_token $SERVICE_TOKEN
#crudini --set /etc/swift/proxy-server.conf "filter:authtoken" auth_token $SERVICE_TOKEN
#crudini --set /etc/swift/proxy-server.conf "filter:authtoken" admin_tenant_name $keystoneservicestenant
#crudini --set /etc/swift/proxy-server.conf "filter:authtoken" admin_user $swiftuser
#crudini --set /etc/swift/proxy-server.conf "filter:authtoken" admin_password $swiftpass
#crudini --set /etc/swift/proxy-server.conf "filter:authtoken" identity_uri http://$keystonehost:35357/
#crudini --set /etc/swift/proxy-server.conf "filter:authtoken" auth_uri http://$keystonehost:5000/

# Welcome Identidy V 3 !!!!!
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" signing_dir /var/cache/swift
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" cache swift.cache
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" username $swiftuser
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" password $swiftpass
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" auth_plugin password
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" project_domain_id $keystonedomain
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" user_domain_id $keystonedomain
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" project_name $keystoneservicestenant
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" auth_uri http://$keystonehost:5000
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" auth_url http://$keystonehost:35357
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" include_service_catalog False
crudini --set /etc/swift/proxy-server.conf "filter:authtoken" auth_version v3

crudini --set /etc/swift/proxy-server.conf "filter:cache" use "egg:swift#memcache"
crudini --set /etc/swift/proxy-server.conf "filter:cache" memcache_servers "127.0.0.1:11211"
crudini --set /etc/swift/proxy-server.conf "filter:catch_errors" use "egg:swift#catch_errors"
crudini --set /etc/swift/proxy-server.conf "filter:healthcheck" use "egg:swift#healthcheck"
crudini --set /etc/swift/proxy-server.conf "filter:proxy-logging" use "egg:swift#proxy_logging"
crudini --set /etc/swift/proxy-server.conf "filter:gatekeeper" use "egg:swift#gatekeeper"


#
# We starts swift proxy and memcached service
#

start memcached
start swift-proxy

update-rc.d memcached enable

#
# And the remaining services
#

start swift-account
start swift-account-auditor
start swift-account-reaper
start swift-account-replicator

start swift-container
start swift-container-auditor
start swift-container-replicator
start swift-container-updater

start swift-object
start swift-object-auditor
start swift-object-replicator
start swift-object-updater

restart swift-account
restart swift-account-auditor
restart swift-account-reaper
restart swift-account-replicator

restart swift-container
restart swift-container-auditor
restart swift-container-replicator
restart swift-container-updater

restart swift-object
restart swift-object-auditor
restart swift-object-replicator
restart swift-object-updater


#
# Then perform more post configuration
#

echo ""
echo "Creating Initial Rings:2"
echo ""

swift-ring-builder /etc/swift/object.builder create $partition_power $replica_count $partition_min_hours
swift-ring-builder /etc/swift/container.builder create $partition_power $replica_count $partition_min_hours
swift-ring-builder /etc/swift/account.builder create $partition_power $replica_count $partition_min_hours

# swift-ring-builder /etc/swift/account.builder add z$swiftfirstzone-$swifthost:6002/$swiftdevice $partition_count
# swift-ring-builder /etc/swift/container.builder add z$swiftfirstzone-$swifthost:6001/$swiftdevice $partition_count
# swift-ring-builder /etc/swift/object.builder add z$swiftfirstzone-$swifthost:6000/$swiftdevice $partition_count

swift-ring-builder /etc/swift/account.builder add --region $swiftfirstregion --zone $swiftfirstzone --ip $swifthost --port 6002 --device $swiftdevice --weight 100
swift-ring-builder /etc/swift/container.builder add --region $swiftfirstregion --zone $swiftfirstzone --ip $swifthost --port 6001 --device $swiftdevice --weight 100
swift-ring-builder /etc/swift/object.builder add --region $swiftfirstregion --zone $swiftfirstzone --ip $swifthost --port 6000 --device $swiftdevice --weight 100

echo ""
echo "Rebalancing Rings:"
echo ""


swift-ring-builder /etc/swift/account.builder rebalance
swift-ring-builder /etc/swift/container.builder rebalance
swift-ring-builder /etc/swift/object.builder rebalance

echo ""
echo "Swift RING Report follows (waiting 10 seconds while you see the report):"
echo ""

swift-ring-builder /etc/swift/account.builder 
swift-ring-builder /etc/swift/container.builder 
swift-ring-builder /etc/swift/object.builder 

sleep 10

echo ""
echo "Continuing"
echo ""

sync
stop swift-proxy
sleep 3
start swift-proxy
sync

#
# More IPTABLES rules to apply
#

iptables -A INPUT -p tcp -m multiport --dports 8080,11211 -j ACCEPT
/etc/init.d/iptables-persistent save

#
# We proceed to restart all swift services
#

swift_svc_start='
	swift-account
	swift-account-auditor
	swift-account-reaper
	swift-account-replicator
	swift-container
	swift-container-auditor
	swift-container-replicator
	swift-container-updater
	swift-object
	swift-object-auditor
	swift-object-replicator
	swift-object-updater
	swift-proxy
'
swift_svc_stop=`echo $swift_svc_start|tac -s' '`

echo ""
echo "Restarting Swift Services"
echo ""

for i in $swift_svc_stop
do
	stop $i
done

sync
sleep 2
sync

for i in $swift_svc_start
do
	start $i
done

sync
sleep 2
sync

echo ""
echo "SWIFT Services:"
echo ""

for i in $swift_svc_start
do
	echo "Status service: $i"
        status $i
	echo ""
done

echo ""
echo "Swift Stat:"
echo ""
source $keystone_fulladmin_rc_file
swift stat 2>/dev/null
sleep 5

echo ""
echo "Ready"
echo ""

#
# Finally, we perform a little check to ensure swift packages are here. If we fail this test,
# we stops the installer from here.
#

testswift=`dpkg -l swift-proxy 2>/dev/null|tail -n 1|grep -ci ^ii`
if [ $testswift == "0" ]
then
	echo ""
	echo "Swift Installation Failed. Aborting !"
	echo ""
	rm -f /etc/openstack-control-script-config/swift
	rm -f /etc/openstack-control-script-config/swift-installed
	exit 0
else
	date > /etc/openstack-control-script-config/swift-installed
	date > /etc/openstack-control-script-config/swift
fi

echo ""
echo "Swift Basic Installation and Configuration Completed"
echo ""

