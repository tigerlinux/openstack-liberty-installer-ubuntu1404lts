#!/bin/bash
#
# Unattended/SemiAutomatted OpenStack Installer
# Reynaldo R. Martinez P.
# E-Mail: TigerLinux@Gmail.com
# OpenStack LIBERTY for Ubuntu 14.04lts
#
#

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

if [ -f ./configs/main-config.rc ]
then
	source ./configs/main-config.rc
	mkdir -p /etc/openstack-control-script-config
else
	echo "Can't Access my Config file. Aborting !"
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

if [ -f /etc/openstack-control-script-config/keystone-extra-idents ]
then
	echo ""
	echo "This module was already completed. Exiting !"
	echo ""
	exit 0
fi


source $keystone_fulladmin_rc_file

echo ""
echo "Creating NOVA Identities"
echo ""

echo "Nova User:"
openstack user create --domain $keystonedomain --password $novapass --email $novaemail $novauser

echo "Nova Role:"
openstack role add --project $keystoneservicestenant --user $novauser $keystoneadminuser

echo "Nova Service:"
openstack service create \
        --name $novasvce \
        --description "OpenStack Compute" \
        compute

#echo "Nova EC2 Service:"
#openstack service create \
#        --name $novaec2svce \
#        --description "OpenStack EC2 Compute" \
#        ec2

echo "Nova Endpoints:"
#openstack endpoint create \
#        --publicurl "http://$novahost:8774/v2/\$(tenant_id)s" \
#        --internalurl "http://$novahost:8774/v2/\$(tenant_id)s" \
#        --adminurl "http://$novahost:8774/v2/\$(tenant_id)s" \
#        --region $endpointsregion \
#        compute

openstack endpoint create --region $endpointsregion \
	compute public http://$novahost:8774/v2/%\(tenant_id\)s

openstack endpoint create --region $endpointsregion \
	compute internal http://$novahost:8774/v2/%\(tenant_id\)s

openstack endpoint create --region $endpointsregion \
	compute admin http://$novahost:8774/v2/%\(tenant_id\)s

#echo "Nova EC2 Endpoint:"
#openstack endpoint create \
#        --publicurl "http://$novahost:8773/services/Cloud" \
#        --internalurl "http://$novahost:8773/services/Cloud" \
#        --adminurl "http://$novahost:8773/services/Cloud" \
#        --region $endpointsregion \
#        ec2

echo "Ready"

echo ""
echo "NOVA Identities Created"
echo ""

