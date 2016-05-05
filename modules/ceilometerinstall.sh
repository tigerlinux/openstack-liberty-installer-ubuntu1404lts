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

if [ -f /etc/openstack-control-script-config/ceilometer-installed ]
then
	echo ""
	echo "This module was already completed. Exiting !"
	echo ""
	exit 0
fi

echo ""
echo "Installing Ceilometer Packages"
echo ""

#
# We install and configure Mongo DB, but ONLY if this is not a compute node
#

if [ $ceilometer_in_compute_node = "no" ]
then

	echo "Installing and Configuring MongoDB Database Backend"
	echo ""
	aptitude -y install mongodb mongodb-clients mongodb-dev mongodb-server
	aptitude -y install libsnappy1 libgoogle-perftools4

	sed -i "s/127.0.0.1/$mondbhost/g" /etc/mongodb.conf
	sed -r -i "s/\#port\ =\ 27017/port\ =\ $mondbport/g" /etc/mongodb.conf
	echo "smallfiles = true" >> /etc/mongodb.conf

	stop mongodb
	stop mongodb
	killall -9 -u mongodb
	rm -f /var/lib/mongodb/journal/prealloc.*
	sleep 2
	sync
	sleep 2
	start mongodb
	sleep 2
	restart mongodb
	sleep 2
	status mongodb
	sync
	sleep 2

	mongo --host $mondbhost --eval "db = db.getSiblingDB(\"$mondbname\");db.addUser({user: \"$mondbuser\",pwd: \"$mondbpass\",roles: [ \"readWrite\", \"dbAdmin\" ]})"
fi

echo ""
echo "Installing Ceilometer Packages"
echo ""

#
# Here, depending if we want to install a ceilometer controller or a ceilometer
# in a compute node, we install the proper packages for the selection
#

export DEBIAN_FRONTEND=noninteractive

if [ $ceilometer_in_compute_node == "no" ]
then
	echo ""
	echo "Packages for Controller or ALL-IN-ONE server"
	echo ""
 
	DEBIAN_FRONTEND=noninteractive aptitude -y install ceilometer-agent-central ceilometer-agent-compute ceilometer-api \
        	ceilometer-collector ceilometer-common python-ceilometer python-ceilometerclient \
	        libnspr4 libnspr4-dev python-libxslt1 python-ceilometermiddleware ceilometer-polling

	if [ $ceilometeralarms == "yes" ]
	then
        	DEBIAN_FRONTEND=noninteractive aptitude -y install ceilometer-alarm-evaluator ceilometer-alarm-notifier \
			ceilometer-agent-notification
	fi
else
	echo ""
	echo "Packages for Compute Node"
	echo ""
	DEBIAN_FRONTEND=noninteractive aptitude -y install ceilometer-agent-compute libnspr4 libnspr4-dev python-libxslt1 \
		ceilometer-polling
fi

#
# FIX - Added extra module for ceilometer
DEBIAN_FRONTEND=noninteractive aptitude -y install python-awsauth

echo "Done"
echo ""

if [ $ceilometer_in_compute_node == "no" ]
then
	stop ceilometer-agent-central
	stop ceilometer-agent-compute
	stop ceilometer-api
	stop ceilometer-collector
	stop ceilometer-polling

 
	if [ $ceilometeralarms == "yes" ]
	then
	        stop ceilometer-alarm-evaluator
        	stop ceilometer-alarm-notifier
	        stop ceilometer-agent-notification
	fi
else
	stop ceilometer-agent-compute
	stop ceilometer-polling
fi

source $keystone_admin_rc_file

echo ""
echo "Configuring Ceilometer"
echo ""

#
# Using python based tools, we proceed to configure ceilometer
#

#
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken admin_tenant_name $keystoneservicestenant
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken admin_user $ceilometeruser
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken admin_password $ceilometerpass
# Deprecated !
#crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_uri http://$keystonehost:5000/v2.0
#crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken identity_uri http://$keystonehost:35357

# New settings for LIBERTY
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_plugin password
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_section keystone_authtoken
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken username $ceilometeruser
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken password $ceilometerpass
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken project_domain_id $keystonedomain
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken user_domain_id $keystonedomain
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken project_name $keystoneservicestenant
# crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_uri http://$keystonehost:5000/v2.0
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_uri http://$keystonehost:5000
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_url http://$keystonehost:35357
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken signing_dir "/tmp/ceilometer-signing-heat"
crudini --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_version v3


# Deprecated !
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT os_auth_url "http://$keystonehost:35357/v2.0"
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT os_tenant_name $keystoneservicestenant
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT os_password $ceilometerpass
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT os_username $ceilometeruser
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT os_auth_region $endpointsregion
 
crudini --set /etc/ceilometer/ceilometer.conf service_credentials os_username $ceilometeruser
crudini --set /etc/ceilometer/ceilometer.conf service_credentials os_password $ceilometerpass
crudini --set /etc/ceilometer/ceilometer.conf service_credentials os_tenant_name $keystoneservicestenant
crudini --set /etc/ceilometer/ceilometer.conf service_credentials os_auth_url http://$keystonehost:5000/v2.0
crudini --set /etc/ceilometer/ceilometer.conf service_credentials os_region_name $endpointsregion
# crudini --set /etc/ceilometer/ceilometer.conf service_credentials os_endpoint_type internalURL
crudini --set /etc/ceilometer/ceilometer.conf service_credentials os_endpoint_type publicURL
 
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT metering_api_port 8777
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT auth_strategy keystone
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT log_dir /var/log/ceilometer
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT os_auth_region $endpointsregion
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT host `hostname`
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT pipeline_cfg_file pipeline.yaml
crudini --set /etc/ceilometer/ceilometer.conf collector workers 2
crudini --set /etc/ceilometer/ceilometer.conf notification workers 2
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT hypervisor_inspector libvirt
 
crudini --del /etc/ceilometer/ceilometer.conf DEFAULT sql_connection > /dev/null 2>&1
crudini --del /etc/ceilometer/ceilometer.conf DEFAULT sql_connection > /dev/null 2>&1
 
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT nova_control_exchange nova
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT glance_control_exchange glance
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT neutron_control_exchange neutron
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT cinder_control_exchange cinder
 
crudini --set /etc/ceilometer/ceilometer.conf publisher telemetry_secret $metering_secret
 
kvm_possible=`grep -E 'svm|vmx' /proc/cpuinfo|uniq|wc -l`
if [ $kvm_possible == "0" ]
then
	crudini --set /etc/ceilometer/ceilometer.conf DEFAULT libvirt_type qemu
else
	crudini --set /etc/ceilometer/ceilometer.conf DEFAULT libvirt_type kvm
fi
 
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT debug false
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT verbose false
crudini --set /etc/ceilometer/ceilometer.conf database connection "mongodb://$mondbuser:$mondbpass@$mondbhost:$mondbport/$mondbname"
crudini --set /etc/ceilometer/ceilometer.conf database metering_time_to_live $mongodbttl
crudini --set /etc/ceilometer/ceilometer.conf database time_to_live $mongodbttl
# Deprecated
# crudini --set /etc/ceilometer/ceilometer.conf rpc_notifier2 topics notifications,glance_notifications
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT notification_topics notifications,glance_notifications
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT notification_topics notifications
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT policy_file policy.json
# crudini --set /etc/ceilometer/ceilometer.conf DEFAULT policy_default_rule default
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT dispatcher database
 
case $brokerflavor in
"qpid")
	crudini --set /etc/ceilometer/ceilometer.conf DEFAULT rpc_backend qpid
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_qpid qpid_hostname $messagebrokerhost
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_qpid qpid_port 5672
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_qpid qpid_username $brokeruser
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_qpid qpid_password $brokerpass
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_qpid qpid_heartbeat 60
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_qpid qpid_protocol tcp
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_qpid qpid_tcp_nodelay True
	;;
 
"rabbitmq")
	crudini --set /etc/ceilometer/ceilometer.conf DEFAULT rpc_backend rabbit
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_host $messagebrokerhost
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_password $brokerpass
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_userid $brokeruser
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_port 5672
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_use_ssl false
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_virtual_host $brokervhost
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_max_retries 0
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_retry_interval 1
	crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_rabbit rabbit_ha_queues false
	;;
esac
 
 
crudini --set /etc/ceilometer/ceilometer.conf alarm evaluation_service ceilometer.alarm.service.SingletonAlarmService
crudini --set /etc/ceilometer/ceilometer.conf alarm partition_rpc_topic alarm_partition_coordination
# crudini --set /etc/ceilometer/ceilometer.conf alarm evaluation_interval 60
# crudini --set /etc/ceilometer/ceilometer.conf alarm record_history True
crudini --set /etc/ceilometer/ceilometer.conf api port 8777
crudini --set /etc/ceilometer/ceilometer.conf api host 0.0.0.0
 
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT heat_control_exchange heat
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT control_exchange ceilometer
crudini --set /etc/ceilometer/ceilometer.conf DEFAULT http_control_exchanges nova
sed -r -i 's/http_control_exchanges\ =\ nova/http_control_exchanges\ =\nova\nhttp_control_exchanges\ =\ glance\nhttp_control_exchanges\ =\ cinder\nhttp_control_exchanges\ =\ neutron\n/' /etc/ceilometer/ceilometer.conf
# crudini --set /etc/ceilometer/ceilometer.conf publisher_rpc metering_topic metering

crudini --set /etc/ceilometer/ceilometer.conf DEFAULT instance_name_template $instance_name_template
crudini --set /etc/ceilometer/ceilometer.conf service_types neutron network
crudini --set /etc/ceilometer/ceilometer.conf service_types nova compute
crudini --set /etc/ceilometer/ceilometer.conf service_types swift object-store
crudini --set /etc/ceilometer/ceilometer.conf service_types glance image
crudini --del /etc/ceilometer/ceilometer.conf service_types kwapi

# April 19, 2016
crudini --set /etc/ceilometer/ceilometer.conf oslo_messaging_notifications topic notifications
crudini --set /etc/ceilometer/ceilometer.conf exchange_control heat_control_exchange heat
crudini --set /etc/ceilometer/ceilometer.conf exchange_control glance_control_exchange glance
crudini --set /etc/ceilometer/ceilometer.conf exchange_control keystone_control_exchange keystone
crudini --set /etc/ceilometer/ceilometer.conf exchange_control cinder_control_exchange cinder
crudini --set /etc/ceilometer/ceilometer.conf exchange_control sahara_control_exchange sahara
crudini --set /etc/ceilometer/ceilometer.conf exchange_control swift_control_exchange swift
crudini --set /etc/ceilometer/ceilometer.conf exchange_control magnum_control_exchange magnum
crudini --set /etc/ceilometer/ceilometer.conf exchange_control trove_control_exchange trove
crudini --set /etc/ceilometer/ceilometer.conf exchange_control nova_control_exchange nova
crudini --set /etc/ceilometer/ceilometer.conf exchange_control neutron_control_exchange neutron
crudini --set /etc/ceilometer/ceilometer.conf publisher_notifier telemetry_driver messagingv2
crudini --set /etc/ceilometer/ceilometer.conf publisher_notifier metering_topic metering
crudini --set /etc/ceilometer/ceilometer.conf publisher_notifier event_topic event
# End April 19, 2016 changes

#
# If this is NOT a compute node, and we are installing swift, then we reconfigure it
# so it can report to ceilometer too
#

if [ $ceilometer_in_compute_node == "no" ]
then
        if [ $swiftinstall == "yes" ]
        then
                # crudini --set /etc/swift/proxy-server.conf filter:ceilometer use "egg:ceilometer#swift"
                crudini --set /etc/swift/proxy-server.conf filter:keystoneauth operator_roles "$keystoneadmintenant,$keystoneuserrole,$keystonereselleradminrole"
                crudini --set /etc/swift/proxy-server.conf pipeline:main pipeline "catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas slo dlo versioned_writes proxy-logging ceilometer proxy-server"
                crudini --set /etc/swift/proxy-server.conf filter:ceilometer paste.filter_factory ceilometermiddleware.swift:filter_factory
                crudini --set /etc/swift/proxy-server.conf filter:ceilometer control_exchange swift
                crudini --set /etc/swift/proxy-server.conf filter:ceilometer driver messagingv2
                crudini --set /etc/swift/proxy-server.conf filter:ceilometer topic notifications
                crudini --set /etc/swift/proxy-server.conf filter:ceilometer log_level WARN
                case $brokerflavor in
                "qpid")
                        crudini --set /etc/swift/proxy-server.conf filter:ceilometer url qpid://$brokeruser:$brokerpass@$messagebrokerhost:5672/
                        ;;
                "rabbitmq")
                        crudini --set /etc/swift/proxy-server.conf filter:ceilometer url rabbit://$brokeruser:$brokerpass@$messagebrokerhost:5672/$brokervhost
                        ;;
                esac
                touch /var/log/ceilometer/swift-proxy-server.log
                chown swift.swift /var/log/ceilometer/swift-proxy-server.log
                usermod -a -G ceilometer swift
		stop swift-proxy
		start swift-proxy
        fi
fi


#
# Ceilometer User need to be part of nova and qemu/kvm/libvirt groups
#

usermod -a -G libvirtd,nova,kvm ceilometer > /dev/null 2>&1

if [ $ceilometer_in_compute_node == "no" ]
then
        ceilometer-dbsync --config-dir /etc/ceilometer/
fi

chown ceilometer.ceilometer /var/log/ceilometer/*

#
# With all configuration done, we proceed to make IPTABLES changes and start ceilometer services
#

echo ""
echo "Applying IPTABLES rules"

iptables -A INPUT -p tcp -m multiport --dports 8777,$mondbport -j ACCEPT
/etc/init.d/iptables-persistent save

echo "Done"

echo ""
echo "Cleaning UP App logs"

for mylog in `ls /var/log/ceilometer/*.log`; do echo "" > $mylog;done

echo "Done"
echo ""

rm -f /var/lib/ceilometer/ceilometer.sqlite

if [ $ceilometer_in_compute_node == "no" ]
then
 
	stop mongodb
 
	sync
	sleep 5
	sync
 
	start mongodb
 
	sync
	sleep 5
	sync
 
	if [ $ceilometer_without_compute == "no" ]
	then
		start ceilometer-agent-compute
		rm -f /etc/init/ceilometer-agent-compute.override
	else
		stop ceilometer-agent-compute
		echo 'manual' > /etc/init/ceilometer-agent-compute.override
	fi
 
	start ceilometer-agent-central
	start ceilometer-api
	start ceilometer-collector
	start ceilometer-polling
 
	if [ $ceilometeralarms == "yes" ]
	then
	        start ceilometer-alarm-notifier
        	start ceilometer-alarm-evaluator
	        start ceilometer-agent-notification
	fi
	
	cp ./libs/ceilometer-expirer-crontab /etc/cron.d/
	
	restart cron
 
else
	start ceilometer-agent-compute
	rm -f /etc/init/ceilometer-agent-compute.override
	start ceilometer-polling
	restart ceilometer-agent-compute
fi

#
# Finally, we test if our packages are correctly installed, and if not, we set a fail
# variable that makes the installer to stop further processing
#

testceilometer=`dpkg -l ceilometer-common 2>/dev/null|tail -n 1|grep -ci ^ii`
if [ $testceilometer == "0" ]
then
	echo ""
	echo "Ceilometer Installation FAILED. Aborting !"
	echo ""
	exit 0
else
	date > /etc/openstack-control-script-config/ceilometer-installed
	date > /etc/openstack-control-script-config/ceilometer
	if [ $ceilometeralarms == "yes" ]
	then
		date > /etc/openstack-control-script-config/ceilometer-installed-alarms
	fi
	if [ $ceilometer_in_compute_node == "no" ]
	then
		date > /etc/openstack-control-script-config/ceilometer-full-installed
	fi
	if [ $ceilometer_without_compute == "yes" ]
	then
		if [ $ceilometer_in_compute_node == "no" ]
		then
			date > /etc/openstack-control-script-config/ceilometer-without-compute
		fi
	fi
fi

echo ""
echo "Ceilometer Installed and Configured"
echo ""



