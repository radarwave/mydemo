#!/bin/bash

# ======================================================================
# Data Directories
# ======================================================================

DATADIRS=`pwd`/datadirs
QDDIR=$DATADIRS/qddir
HDFSDIR=$DATADIRS/qddir/hdfs_gpsql

SEG_PREFIX=demoDataDir

declare -a DIRVEC=($DATADIRS/dbfast1 \
                   $DATADIRS/dbfast2 \
                   $DATADIRS/dbfast3 )

declare -a DIRVEC_MIRROR=($DATADIRS/dbfast_mirror1 \
                          $DATADIRS/dbfast_mirror2 \
                          $DATADIRS/dbfast_mirror3 )

# ======================================================================
# DATABASE PORTS
# ======================================================================

DEMO_SEG_PORTS=$DEMO_PORT_BASE

#******************************************************************************
# Functions
#******************************************************************************

checkDemoConfig(){
    echo "Checking for port availability... "
    # Check if Master_DEMO_Port is free
    echo "Checking if port ${MASTER_DEMO_PORT} is available"
    PORT_FILE="/tmp/.s.PGSQL.${MASTER_DEMO_PORT}"
    if [ -f ${PORT_FILE} -o  -S ${PORT_FILE} ] ; then 
        echo ""
        echo -n " Port ${MASTER_DEMO_PORT} appears to be in use. " 
        echo " This port is needed by the Master Database instance. "
        echo ">>> Edit Makefile to correct the port number (MASTER_PORT). <<<" 
        echo -n " Check to see if the port is free by using : "
        echo " 'netstat -an | grep ${MASTER_DEMO_PORT}"
        echo ""
        return 1
    fi

    echo "Checking if port ${DEMO_SEG_PORTS} is available"
    PORT_FILE="/tmp/.s.PGSQL.${DEMO_SEG_PORTS}"
    if [ -f ${PORT_FILE} -o -S ${PORT_FILE} ] ; then 
        echo ""
        echo -n "Port ${DEMO_SEG_PORTS} appears to be in use."
        echo " This port is needed for segment database instance."
        echo ">>> Edit Makefile to correct the base ports (PORT_BASE). <<<"
        echo -n " Check to see if the port is free by using : "
        echo " 'netstat -an | grep ${DEMO_SEG_PORTS}"
        echo ""
        return 1
    fi
    return 0
}

USAGE(){
    echo ""
    echo " `basename $0` -c -d -u"
    echo " -c : check if demo is possible."
    echo " -d : Delete the demo."
    echo " -u : Usage, prints this message."
    echo ""
}

#
# Clean up the demo
#

cleanDemo(){

    ##
    ## Attempt to bring down using GPDB cluster instance
    ##

    (export MASTER_DATA_DIRECTORY=$QDDIR/${SEG_PREFIX}-1;
     source ${GPHOME}/greenplum_path.sh;
     if [ "${ENABLE_HDFS}" = "true" ]; then
         [ -f cluster_env.sh ] && source cluster_env.sh;
         psql postgres -c "drop database hdfs";
         psql postgres -c "drop tablespace hdfs_tablespace";
     fi;
     hawq stop master -a
     hawq stop segment -a)

    ##
    ## Remove the files and directories created; allow test harnesses
    ## to disable this
    ##

    if [ "${GPDEMO_DESTRUCTIVE_CLEAN}" != "false" ]; then
        if [ -f hostfile ];  then
            echo "Deleting hostfile"
            rm -f hostfile
        fi
        if [ -f clusterConfigFile ];  then
            echo "Deleting clusterConfigFile"
            rm -f clusterConfigFile
        fi
        if [ -d ${DATADIRS} ];  then
            echo "Deleting ${DATADIRS}"
            rm -rf ${DATADIRS}
        fi
        if [ -d logs ];  then
            rm -rf logs
        fi
    fi
}

#*****************************************************************************
# Main Section
#*****************************************************************************

while getopts ":cd'?'" opt
		do
		case $opt in 
				'?' ) USAGE ;;
                c) checkDemoConfig
                    RETVAL=$?
                    if [ $RETVAL -ne 0 ]; then
                        echo "Checking failed "
                        exit 1
                    fi
                    exit 0
                ;;
                d) cleanDemo
                   exit 0
                ;;
                *) USAGE
                   exit 0
                   ;;
		esac
done

if [ x"$GPHOME" = x ]; then
        echo ""
        echo "GPHOME is not set.  Point to the location"
        echo "of the Greenplum installation directory."
        echo ""
        exit 1
else
    GPSEARCH=$GPHOME
fi

cat <<-EOF

	**********************************************************************
	This is a demo of the HAWQ Database module.  We'll perform a
	local cluster installation with 1 master instance and 1 segment
	instances all on this machine.

	  GPHOME=${GPHOME}
	  MASTER_DATA_DIRECTORY=$QDDIR/${SEG_PREFIX}-1

	In order to run the Greenplum Database module, you must have the
	GPHOME environment variable set to the location of the Greenplum
	install.  You must also have the following port numbers free:

	  ${MASTER_DEMO_PORT}
	  ${DEMO_SEG_PORTS}

	**********************************************************************

EOF

GPPATH=`find $GPSEARCH -name gpfdist | tail -1`
RETVAL=$?

if [ "$RETVAL" -ne 0 ]; then
    echo "Error attempting to find Greenplum executables in $GPSEARCH"
    exit 1
fi

if [ ! -x "$GPPATH" ]; then
    echo "No executables found for Greenplum installation in $GPSEARCH"
    exit 1
fi
GPPATH=`dirname $GPPATH`
if [ ! -x $GPPATH/gpinitsystem ]; then
    echo "No mgmt executables found for Greenplum installation in $GPPATH"
    exit 1
fi

if [ -d $DATADIRS ]; then
  rm -rf $DATADIRS
fi
mkdir $DATADIRS
mkdir $QDDIR
if [ "${ENABLE_HDFS}" = "true" ]; then
    mkdir $HDFSDIR
fi

for dir in ${DIRVEC[@]} ${DIRVEC_MIRROR[@]}
do
  if [ ! -d $dir ]; then
    mkdir $dir
  fi
done

#*****************************************************************************************
# Host configuration
#*****************************************************************************************

LOCALHOST=`hostname`
echo $LOCALHOST > hostfile
echo $LOCALHOST > ${GPHOME}/slaves 

#*****************************************************************************************
# Name of the system configuration file.
#*****************************************************************************************

CLUSTER_CONFIG=clusterConfigFile
CLUSTER_CONFIG_POSTGRES_ADDONS=clusterConfigPostgresAddonsFile

rm -f ${CLUSTER_CONFIG}
rm -f ${CLUSTER_CONFIG_POSTGRES_ADDONS}

#*****************************************************************************************
# Create the system configuration file
#*****************************************************************************************

#*****************************************************************************************
# Create environment file
#*****************************************************************************************

cat > cluster_env.sh <<-EOF
	export MASTER_DATA_DIRECTORY=$QDDIR/${SEG_PREFIX}-1
	export PGPORT=${MASTER_DEMO_PORT}
EOF

# Change hawq-site.xml
DATE=$( date +%Y%m%dt%H%M%S )
HDFS_HOST=${HDFS_HOST:=localhost:8020}

SEGMENT_PORT="${DEMO_SEG_PORTS}"
NAMENODE_HOST=`echo ${HDFS_HOST} | cut -d":" -f1`
NAMENODE_PORT=`echo ${HDFS_HOST} | cut -d":" -f2`
HAWQ_FILE_SPACE=gpsql/gpdb${DATE}
MASTER_DIRECTORY=$QDDIR/masterdd
SEGMENT_DIRECTORY=$QDDIR/segmentdd
MASTER_TEMP_DIRECTORY=$QDDIR/master_temp
SEGMENT_TEMP_DIRECTORY=$QDDIR/segment_temp
ENABLE_YARN=${YARN:=none}
mkdir -p ${MASTER_DIRECTORY} ${MASTER_TEMP_DIRECTORY}
rm -rf ${MASTER_DIRECTORY}/* 
mkdir -p ${SEGMENT_DIRECTORY} ${SEGMENT_TEMP_DIRECTORY}
rm -rf ${SEGMENT_DIRECTORY}/* 

# Replace hawq-site.xml with the template.
cp ${GPHOME}/etc/template-hawq-site.xml ${GPHOME}/etc/hawq-site.xml

sed -e "s|%master.host%|${LOCALHOST}|" \
    -e "s|%master.port%|${MASTER_DEMO_PORT}|" \
    -e "s|%master.directory%|${MASTER_DIRECTORY}|" \
    -e "s|%master.temp.directory%|${MASTER_TEMP_DIRECTORY}|" \
    -e "s|%standby.host%|None|" \
    -e "s|%segment.port%|${SEGMENT_PORT}|" \
    -e "s|%segment.directory%|${SEGMENT_DIRECTORY}|" \
    -e "s|%segment.temp.directory%|${SEGMENT_TEMP_DIRECTORY}|" \
    -e "s|%enable_yarn%|${ENABLE_YARN}|" \
    -e "s|%namenode.host%|${NAMENODE_HOST}|" \
    -e "s|%namenode.port%|${NAMENODE_PORT}|" \
    -e "s|%hawq.file.space%|${HAWQ_FILE_SPACE}|" \
    --in-place=.orig ${GPHOME}/etc/hawq-site.xml

echo "${LOCALHOST}" > ${GPHOME}/slaves

#*****************************************************************************************
# Create cluster
#*****************************************************************************************

if [ "${BUILD_TYPE}" = "gcov" ] && [ -f "${CLUSTER_CONFIG_POSTGRES_ADDONS}" ]; then
    echo "executing: $GPPATH/gpinitsystem -a -c $CLUSTER_CONFIG -p ${CLUSTER_CONFIG_POSTGRES_ADDONS} \"$@\""
    $GPPATH/gpinitsystem -a -c $CLUSTER_CONFIG -p ${CLUSTER_CONFIG_POSTGRES_ADDONS} "$@"
else
    source ${GPHOME}/greenplum_path.sh;
    echo "========================================"
    echo "HAWQ master init started:"
    echo "========================================"
    hawq init master -a
    echo "========================================"
    echo "HAWQ segment init started:"
    echo "========================================"
    hawq init segment -a
    echo "========================================"
fi

RETURN=$?
echo "========================================"
echo "gpinitsystem returned: ${RETURN}"
echo "========================================"

exit ${RETURN}
