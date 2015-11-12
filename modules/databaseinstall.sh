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
# First, we source our config file.
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
# If we configured the "dbpopulate" variable to "no", we basically
# assume all database related procedures are completed
#

if [ $dbpopulate == "no" ]
then
	echo "We will not populate the databases"
	date > /etc/openstack-control-script-config/db-installed
	exit 0
fi

if [ -f /etc/openstack-control-script-config/db-installed ]
then
	echo ""
	echo "This module was already completed. Exiting !"
	echo ""
	exit 0
fi

#
# If we are going to install database services (dbinstall=yes), then, depending of what
# we choose as "dbflavor", we proceed to install and configure the software and it's root
# access.
#

if [ $dbinstall == "yes" ]
then
	echo "Installing Database Support"
	case $dbflavor in
	"mysql")
		echo "Installing MySQL Server"
		rm -f /root/.my.cnf

		#
		# We preseed first the mysql/mariadb root password
		#
		echo "mysql-server-5.5 mysql-server/root_password_again password $mysqldbpassword" > /tmp/mysql-seed.txt
		echo "mysql-server-5.5 mysql-server/root_password password $mysqldbpassword" >> /tmp/mysql-seed.txt
		echo "mariadb-server-5.5 mysql-server/root_password_again password $mysqldbpassword" >> /tmp/mysql-seed.txt
		echo "mariadb-server-5.5 mysql-server/root_password password $mysqldbpassword" >> /tmp/mysql-seed.txt
		debconf-set-selections /tmp/mysql-seed.txt
		# No more mysql - we'll use MariaDB !!
		aptitude -y install mariadb-server-5.5 mariadb-client-5.5
		sed -r -i 's/127\.0\.0\.1/0\.0\.0\.0/' /etc/mysql/my.cnf
		service mysql restart
		update-rc.d mysql enable
		sleep 5
		echo "[client]" > /root/.my.cnf
		echo "user=$mysqldbadm" >> /root/.my.cnf
		echo "password=$mysqldbpassword" >> /root/.my.cnf
		echo "GRANT ALL PRIVILEGES ON *.* TO '$mysqldbadm'@'%' IDENTIFIED BY '$mysqldbpassword' WITH GRANT OPTION;"|mysql
		echo "GRANT ALL PRIVILEGES ON *.* TO '$mysqldbadm'@'$dbbackendhost' IDENTIFIED BY '$mysqldbpassword' WITH GRANT OPTION;"|mysql
		echo "FLUSH PRIVILEGES;"|mysql
		iptables -A INPUT -p tcp -m multiport --dports $mysqldbport -j ACCEPT
		/etc/init.d/iptables-persistent save
		rm -f /tmp/mysql-seed.txt
		echo "MySQL Server Installed"
		;;
	"postgres")
		echo "Installing PostgreSQL Server"
		rm -f /root/.pgpass
		apt-get -y install postgresql postgresql-client
		/etc/init.d/postgresql restart
		update-rc.d postgresql enable
		sleep 5
		su - $psqldbadm -c "echo \"ALTER ROLE $psqldbadm WITH PASSWORD '$psqldbpassword';\"|psql"
		sleep 5
		sync
		echo "listen_addresses = '*'" >> /etc/postgresql/9.3/main/postgresql.conf
		echo "port = 5432" >> /etc/postgresql/9.3/main/postgresql.conf
		echo -e "host\tall\tall\t0.0.0.0 0.0.0.0\tmd5" >> /etc/postgresql/9.3/main/pg_hba.conf
		/etc/init.d/postgresql restart
		sleep 5
		sync
		echo "*:*:*:$psqldbadm:$psqldbpassword" > /root/.pgpass
		chmod 0600 /root/.pgpass
		iptables -A INPUT -p tcp -m multiport --dports $psqldbport -j ACCEPT
		/etc/init.d/iptables-persistent save
		echo "PostgreSQL Server Installed"
		;;
	esac
fi

#
# Here, we verify if the software was properlly installed. If not, then we fail and make
# a full stop in the main installer.
#

if [ $dbinstall == "yes" ]
then
	case $dbflavor in
	"mysql")
		testmysql=`dpkg -l mariadb-server-5.5 2>/dev/null|tail -n 1|grep -ci ^ii`
		if [ $testmysql == "0" ]
		then
			echo ""
			echo "MySQL-Server Installation FAILED. Aborting !"
			echo ""
			exit 0
		else
			date > /etc/openstack-control-script-config/db-installed
		fi
		;;
	"postgres")
		testpgsql=`dpkg -l postgresql 2>/dev/null|tail -n 1|grep -ci ^ii`
		if [ $testpgsql == "0" ]
		then
			echo ""
			echo "PostgreSQL-Server Installation FAILED. Aborting !"
			echo ""
			exit 0
		else
			date > /etc/openstack-control-script-config/db-installed
		fi
		;;
	esac
fi

#
# The following two variables are used later in the database creation section
#

mysqlcommand="mysql --port=$mysqldbport --password=$mysqldbpassword --user=$mysqldbadm --host=$dbbackendhost"
psqlcommand="psql -U $psqldbadm --host $dbbackendhost -p $psqldbport"

#
# If we choose to create the databases (dbcreate=yes), then we proceed here to do it. Even if we choose not to
# install some modules, we proceed to create all possible databases for the OpenStack Cloud.
#
#
# At the end of this sequence, we test with one of the databases (horizon) so we can decide
# if the proccess was successfull or not
#

if [ $dbcreate == "yes" ]
then
	echo "Creating OpenStack Databases"
	case $dbflavor in
	"mysql")
		echo "[client]" > /root/.my.cnf
		echo "user=$mysqldbadm" >> /root/.my.cnf
		echo "password=$mysqldbpassword" >> /root/.my.cnf
		echo "Keystone:"
		echo "CREATE DATABASE $keystonedbname default character set utf8;"|$mysqlcommand
		echo "GRANT ALL ON $keystonedbname.* TO '$keystonedbuser'@'%' IDENTIFIED BY '$keystonedbpass';"|$mysqlcommand
		echo "GRANT ALL ON $keystonedbname.* TO '$keystonedbuser'@'localhost' IDENTIFIED BY '$keystonedbpass';"|$mysqlcommand
		echo "GRANT ALL ON $keystonedbname.* TO '$keystonedbuser'@'$keystonehost' IDENTIFIED BY '$keystonedbpass';"|$mysqlcommand
		for extrahost in $extrakeystonehosts
		do
			echo "GRANT ALL ON $keystonedbname.* TO '$keystonedbuser'@'$extrahost' IDENTIFIED BY '$keystonedbpass';"|$mysqlcommand
		done
		echo "FLUSH PRIVILEGES;"|$mysqlcommand
		sync
		sleep 5
		sync

		echo "Glance:"
		echo "CREATE DATABASE $glancedbname default character set utf8;"|$mysqlcommand
		echo "GRANT ALL ON $glancedbname.* TO '$glancedbuser'@'%' IDENTIFIED BY '$glancedbpass';"|$mysqlcommand
		echo "GRANT ALL ON $glancedbname.* TO '$glancedbuser'@'localhost' IDENTIFIED BY '$glancedbpass';"|$mysqlcommand
		echo "GRANT ALL ON $glancedbname.* TO '$glancedbuser'@'$glancehost' IDENTIFIED BY '$glancedbpass';"|$mysqlcommand
		for extrahost in $extraglancehosts
		do
			echo "GRANT ALL ON $glancedbname.* TO '$glancedbuser'@'$extrahost' IDENTIFIED BY '$glancedbpass';"|$mysqlcommand
		done
		echo "FLUSH PRIVILEGES;"|$mysqlcommand
		sync
		sleep 5
		sync

		echo "Cinder:"
		echo "CREATE DATABASE $cinderdbname default character set utf8;"|$mysqlcommand
		echo "GRANT ALL ON $cinderdbname.* TO '$cinderdbuser'@'%' IDENTIFIED BY '$cinderdbpass';"|$mysqlcommand
		echo "GRANT ALL ON $cinderdbname.* TO '$cinderdbuser'@'localhost' IDENTIFIED BY '$cinderdbpass';"|$mysqlcommand
		echo "GRANT ALL ON $cinderdbname.* TO '$cinderdbuser'@'$cinderhost' IDENTIFIED BY '$cinderdbpass';"|$mysqlcommand
		for extrahost in $extracinderhosts
		do
			echo "GRANT ALL ON $cinderdbname.* TO '$cinderdbuser'@'$extrahost' IDENTIFIED BY '$cinderdbpass';"|$mysqlcommand
		done
		echo "FLUSH PRIVILEGES;"|$mysqlcommand
		sync
		sleep 5
		sync

		echo "Neutron:"
		echo "CREATE DATABASE $neutrondbname default character set utf8;"|$mysqlcommand
		echo "GRANT ALL ON $neutrondbname.* TO '$neutrondbuser'@'%' IDENTIFIED BY '$neutrondbpass';"|$mysqlcommand
		echo "GRANT ALL ON $neutrondbname.* TO '$neutrondbuser'@'localhost' IDENTIFIED BY '$neutrondbpass';"|$mysqlcommand
		echo "GRANT ALL ON $neutrondbname.* TO '$neutrondbuser'@'$neutronhost' IDENTIFIED BY '$neutrondbpass';"|$mysqlcommand
		for extrahost in $extraneutronhosts
		do
			echo "GRANT ALL ON $neutrondbname.* TO '$neutrondbuser'@'$extrahost' IDENTIFIED BY '$neutrondbpass';"|$mysqlcommand
		done
		echo "FLUSH PRIVILEGES;"|$mysqlcommand
		sync
		sleep 5
		sync

		echo "Nova:"
		echo "CREATE DATABASE $novadbname default character set utf8;"|$mysqlcommand
		echo "GRANT ALL ON $novadbname.* TO '$novadbuser'@'%' IDENTIFIED BY '$novadbpass';"|$mysqlcommand
		echo "GRANT ALL ON $novadbname.* TO '$novadbuser'@'localhost' IDENTIFIED BY '$novadbpass';"|$mysqlcommand
		echo "GRANT ALL ON $novadbname.* TO '$novadbuser'@'$novahost' IDENTIFIED BY '$novadbpass';"|$mysqlcommand
		for extrahost in $extranovahosts
		do
			echo "GRANT ALL ON $novadbname.* TO '$novadbuser'@'$extrahost' IDENTIFIED BY '$novadbpass';"|$mysqlcommand
		done
		echo "FLUSH PRIVILEGES;"|$mysqlcommand
		sync
		sleep 5
		sync

		echo "Heat:"
		echo "CREATE DATABASE $heatdbname default character set utf8;"|$mysqlcommand
		echo "GRANT ALL ON $heatdbname.* TO '$heatdbuser'@'%' IDENTIFIED BY '$heatdbpass';"|$mysqlcommand
		echo "GRANT ALL ON $heatdbname.* TO '$heatdbuser'@'localhost' IDENTIFIED BY '$heatdbpass';"|$mysqlcommand
		echo "GRANT ALL ON $heatdbname.* TO '$heatdbuser'@'$heathost' IDENTIFIED BY '$heatdbpass';"|$mysqlcommand
		for extrahost in $extraheathosts
		do
			echo "GRANT ALL ON $heatdbname.* TO '$heatdbuser'@'$extrahost' IDENTIFIED BY '$heatdbpass';"|$mysqlcommand
		done
		echo "FLUSH PRIVILEGES;"|$mysqlcommand
		sync
		sleep 5
		sync

		echo "Horizon:"
		echo "CREATE DATABASE $horizondbname default character set utf8;"|$mysqlcommand
		echo "GRANT ALL ON $horizondbname.* TO '$horizondbuser'@'%' IDENTIFIED BY '$horizondbpass';"|$mysqlcommand
		echo "GRANT ALL ON $horizondbname.* TO '$horizondbuser'@'localhost' IDENTIFIED BY '$horizondbpass';"|$mysqlcommand
		echo "GRANT ALL ON $horizondbname.* TO '$horizondbuser'@'$horizonhost' IDENTIFIED BY '$horizondbpass';"|$mysqlcommand
		for extrahost in $extrahorizonhosts
		do
			echo "GRANT ALL ON $horizondbname.* TO '$horizondbuser'@'$extrahost' IDENTIFIED BY '$horizondbpass';"|$mysqlcommand
		done
		echo "FLUSH PRIVILEGES;"|$mysqlcommand
		sync
		sleep 5
		sync

                echo "Trove:"
                echo "CREATE DATABASE $trovedbname default character set utf8;"|$mysqlcommand
                echo "GRANT ALL ON $trovedbname.* TO '$trovedbuser'@'%' IDENTIFIED BY '$trovedbpass';"|$mysqlcommand
                echo "GRANT ALL ON $trovedbname.* TO '$trovedbuser'@'localhost' IDENTIFIED BY '$trovedbpass';"|$mysqlcommand
                echo "GRANT ALL ON $trovedbname.* TO '$trovedbuser'@'$trovehost' IDENTIFIED BY '$trovedbpass';"|$mysqlcommand
                for extrahost in $extratrovehosts
                do
                        echo "GRANT ALL ON $trovedbname.* TO '$trovedbuser'@'$extrahost' IDENTIFIED BY '$trovedbpass';"|$mysqlcommand
                done
                echo "FLUSH PRIVILEGES;"|$mysqlcommand
                sync
                sleep 5
                sync

                echo "Sahara:"
                echo "CREATE DATABASE $saharadbname default character set utf8;"|$mysqlcommand
                echo "GRANT ALL ON $saharadbname.* TO '$saharadbuser'@'%' IDENTIFIED BY '$saharadbpass';"|$mysqlcommand
                echo "GRANT ALL ON $saharadbname.* TO '$saharadbuser'@'localhost' IDENTIFIED BY '$saharadbpass';"|$mysqlcommand
                echo "GRANT ALL ON $saharadbname.* TO '$saharadbuser'@'$saharahost' IDENTIFIED BY '$saharadbpass';"|$mysqlcommand
                for extrahost in $extrasaharahosts
                do
                        echo "GRANT ALL ON $saharadbname.* TO '$saharadbuser'@'$extrahost' IDENTIFIED BY '$saharadbpass';"|$mysqlcommand
                done
                echo "FLUSH PRIVILEGES;"|$mysqlcommand
                sync
                sleep 5
                sync


		echo ""
		echo "Databases Created:"
		echo "show databases;"|$mysqlcommand

		checkdbcreation=`echo "show databases;"|$mysqlcommand|grep -ci $horizondbname`
		if [ $checkdbcreation == "0" ]
		then
			echo ""
			echo "Database Creation FAILED. Aborting !"
			echo ""
			rm -f /etc/openstack-control-script-config/db-installed
			exit 0
		else
			date > /etc/openstack-control-script-config/db-installed
		fi

		echo ""

		;;
	"postgres")
		echo "*:*:*:$psqldbadm:$psqldbpassword" > /root/.pgpass
		chmod 0600 /root/.pgpass
		echo "Keystone:"
		echo "CREATE user $keystonedbuser;"|$psqlcommand
		echo "ALTER user $keystonedbuser with password '$keystonedbpass'"|$psqlcommand
		echo "CREATE DATABASE $keystonedbname"|$psqlcommand
		echo "GRANT ALL PRIVILEGES ON database $keystonedbname TO $keystonedbuser;"|$psqlcommand
		sync
		sleep 5
		sync

		echo "Glance:"
		echo "CREATE user $glancedbuser;"|$psqlcommand
		echo "ALTER user $glancedbuser with password '$glancedbpass'"|$psqlcommand
		echo "CREATE DATABASE $glancedbname"|$psqlcommand
		echo "GRANT ALL PRIVILEGES ON database $glancedbname TO $glancedbuser;"|$psqlcommand
		sync
		sleep 5
		sync

		echo "Cinder:"
		echo "CREATE user $cinderdbuser;"|$psqlcommand
		echo "ALTER user $cinderdbuser with password '$cinderdbpass'"|$psqlcommand
		echo "CREATE DATABASE $cinderdbname"|$psqlcommand
		echo "GRANT ALL PRIVILEGES ON database $cinderdbname TO $cinderdbuser;"|$psqlcommand
		sync
		sleep 5
		sync

		echo "Neutron:"
		echo "CREATE user $neutrondbuser;"|$psqlcommand
		echo "ALTER user $neutrondbuser with password '$neutrondbpass'"|$psqlcommand
		echo "CREATE DATABASE $neutrondbname"|$psqlcommand
		echo "GRANT ALL PRIVILEGES ON database $neutrondbname TO $neutrondbuser;"|$psqlcommand
		sync
		sleep 5
		sync

		echo "Nova:" 
		echo "CREATE user $novadbuser;"|$psqlcommand
		echo "ALTER user $novadbuser with password '$novadbpass'"|$psqlcommand
		echo "CREATE DATABASE $novadbname"|$psqlcommand
		echo "GRANT ALL PRIVILEGES ON database $novadbname TO $novadbuser;"|$psqlcommand
		sync
		sleep 5
		sync

		echo "Heat:" 
		echo "CREATE user $heatdbuser;"|$psqlcommand
		echo "ALTER user $heatdbuser with password '$heatdbpass'"|$psqlcommand
		echo "CREATE DATABASE $heatdbname"|$psqlcommand
		echo "GRANT ALL PRIVILEGES ON database $heatdbname TO $heatdbuser;"|$psqlcommand
		sync
		sleep 5
		sync

		echo "Horizon:" 
		echo "CREATE user $horizondbuser;"|$psqlcommand
		echo "ALTER user $horizondbuser with password '$horizondbpass'"|$psqlcommand
		echo "CREATE DATABASE $horizondbname"|$psqlcommand
		echo "GRANT ALL PRIVILEGES ON database $horizondbname TO $horizondbuser;"|$psqlcommand
		sync
		sleep 5
		sync

                echo "Trove:" 
                echo "CREATE user $trovedbuser;"|$psqlcommand
                echo "ALTER user $trovedbuser with password '$trovedbpass'"|$psqlcommand
                echo "CREATE DATABASE $trovedbname"|$psqlcommand
                echo "GRANT ALL PRIVILEGES ON database $trovedbname TO $trovedbuser;"|$psqlcommand
                sync
                sleep 5
                sync

                echo "Sahara:"
                echo "CREATE user $saharadbuser;"|$psqlcommand
                echo "ALTER user $saharadbuser with password '$saharadbpass'"|$psqlcommand
                echo "CREATE DATABASE $saharadbname"|$psqlcommand
                echo "GRANT ALL PRIVILEGES ON database $saharadbname TO $saharadbuser;"|$psqlcommand
                sync
                sleep 5
                sync


		echo ""
		echo "Databases Created:"
		echo "\list"|$psqlcommand

		checkdbcreation=`echo "\list"|$psqlcommand|grep -ci $horizondbname`
		if [ $checkdbcreation == "0" ]
		then
			echo ""
			echo "Database Creation FAILED. Aborting !"
			echo ""
			rm -f /etc/openstack-control-script-config/db-installed
			exit 0
		else
			date > /etc/openstack-control-script-config/db-installed
		fi

		echo ""
		;;
	esac
fi

echo ""
echo "Database Proccess Completed"
echo ""
