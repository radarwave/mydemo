# ======================================================================
# Makefile for Demo
# ======================================================================

SHELL=/bin/bash

# ----------------------------------------------------------------------
# VARIABLES
# ----------------------------------------------------------------------

MASTER_PORT=18501
PORT_BASE=18506

all: clean check cluster probe

cluster:	
	@ echo ""
	@echo "Building cluster, this may take a few minutes."
	@- MASTER_DEMO_PORT=$(MASTER_PORT) DEMO_PORT_BASE=$(PORT_BASE) YARN=${YARN} \
		./demo_cluster.sh 
	@echo ""

SCHEDULE=schedule_basic

cdbfast:
	source ../greenplum-db-devel/greenplum_path.sh; \
	source cluster_env.sh; \
	hawq cluster start; \
	cd ../test/featuretest; \
	./gptest.py -t $(SCHEDULE) 2>&1 | tee gptest.out; \
	hawq cluster stop

tinc:
	source ../greenplum-db-devel/greenplum_path.sh; \
	source cluster_env.sh; \
	hawq cluster start; \
	cd ../test/featuretest_tinc/Release-0_1_5_0-branch; \
	source tinc_env.sh; \
	tinc.py discover -s tincrepo/interconnect > tinctest.log 2>&1; \
	hawq cluster stop

probe:
	@ echo "Probing the databases "
	@ echo ""
	@ MASTER_DEMO_PORT=$(MASTER_PORT) DEMO_PORT_BASE=$(PORT_BASE) \
		./probe_config.sh
	@ echo "Probe finished"

.PHONY : clean 

check: 
	@ echo ""
	@ echo "Checking port availability... "
	@ echo ""
	@MASTER_DEMO_PORT=$(MASTER_PORT) DEMO_PORT_BASE=$(PORT_BASE)  \
		./demo_cluster.sh -c
	@echo ""
	@ echo "Checking completed without any errors...."
	@echo ""

clean:
	@ echo "Deleting cluster.... "
	@DEMO_PORT_BASE=$(PORT_BASE) ./demo_cluster.sh -d
	@echo ""
