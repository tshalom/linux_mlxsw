#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# This is a hacked-up version of qos_pfc.sh adjusted to be plugged into a VM,
# instead of running as a selftest. Just for debugging purposes.
#
#                                                       +---------------------+
#                                                       |                  H2 |
#                                                       | + $h2.222           |
#                                                       | | 192.0.2.65/28     |
#                                   HOST                | | e-qos-map 0:2     |
#                                                       | |                   |
#                                   ^                   | + $h2               |
#                                   |                   +-|-------------------+
#                                   |                     |
# +---------------------------------|---------------------|-------------------+
# |                                 + $swp1               + $swp2             |
# |                                 | iPOOL1              | iPOOL2            |
# |                                 | ePOOL4              | ePOOL4            |
# |                                 | 1Gbps               | >1Gbps            |
# |                                 | PFC:enabled=1       |                   |
# |                                 | ETS:1-to-1,strict   |                   |
# |                              +--|----------------+ +--|----------------+  |
# |                              |  + $swp1.111      | |  + $swp2.222      |  |
# |                              |                   | |                   |  |
# |                              |  BR111            | |  BR222            |  |
# |                              |                   | |                   |  |
# |                              |  + $swp3.111      | |  + $swp3.222      |  |
# |                              +--|----------------+ +--|----------------+  |
# |                                 \_____________________/                   |
# | iPOOL0: 500KB dynamic                 |                                   |
# | iPOOL1: 10MB static                   + $swp3                             |
# | iPOOL2: 1MB static                    | 1Gbps bottleneck                  |
# | ePOOL4: 500KB dynamic                 | iPOOL0                            |
# | ePOOL5: 10MB static                   | ePOOL6                            |
# | ePOOL6: 1MB static                    | ETS:1-to-1,strict                 |
# +---------------------------------------|-----------------------------------+
#                                         |
#                    +--------------------|--------------------+
#                    |                    + $h3             H3 |
#                    |                   / \                   |
#                    |                  /   \                  |
#                    |         $h3.111 +     + $h3.222         |
#                    |  192.0.2.34/28          192.0.2.66/28   |
#                    +-----------------------------------------+

ALL_TESTS="
	ping_ipv4
	test_qos_pfc
"

lib_dir=$(dirname $0)/../../../net/forwarding

NUM_NETIFS=6
source $lib_dir/lib.sh
source $lib_dir/devlink_lib.sh
source qos_lib.sh

h2_create()
{
	simple_if_init $h2
	mtu_set $h2 10000

	vlan_create $h2 222 v$h2 192.0.2.65/28
	ip link set dev $h2.222 type vlan egress-qos-map 0:2
}

h2_destroy()
{
	vlan_destroy $h2 222

	mtu_restore $h2
	simple_if_fini $h2
}

h3_create()
{
	simple_if_init $h3
	mtu_set $h3 10000

	vlan_create $h3 111 v$h3 192.0.2.34/28
	vlan_create $h3 222 v$h3 192.0.2.66/28
}

h3_destroy()
{
	vlan_destroy $h3 222
	vlan_destroy $h3 111

	mtu_restore $h3
	simple_if_fini $h3
}

switch_create()
{
    	local _1KB=1000
	local _1MB=$((1000 * _1KB))
	local _10MB=$((10 * _1MB))
	local _500KB=$((500 * _1KB))
	local _1_5MB=$((1500 * _1KB))

	# pools
	# -----

	devlink_pool_size_thtype_save 0 dynamic
	devlink_pool_size_thtype_save 1 static
	devlink_pool_size_thtype_save 2 static
	devlink_pool_size_thtype_save 4 dynamic
	devlink_pool_size_thtype_save 5 static
	devlink_pool_size_thtype_save 6 static

	devlink_port_pool_th_save $swp2 2
	devlink_port_pool_th_save $swp3 6
	devlink_port_pool_th_save $swp1 1

	devlink_tc_bind_pool_th_save $swp2 2 ingress
	devlink_tc_bind_pool_th_save $swp3 1 egress
	devlink_tc_bind_pool_th_save $swp3 2 egress
	devlink_tc_bind_pool_th_save $swp1 1 ingress

	# Pools 0 and 4 are used for ingress / egress of uninteresting traffic.
	# Just reduce the size. Keep them dynamic so that we don't need to
	# change all the uninteresting quotas.
	devlink_pool_size_thtype_set 0 dynamic $_500KB
	devlink_pool_size_thtype_set 4 dynamic $_500KB

	# Pool 1 is used for ingress of paused lossless traffic (through $swp1)
	# and for ingress of congested lossless traffic (through $swp1).
	devlink_pool_size_thtype_set 1 static $_10MB

    	# Pool 2 is used for ingress of congested high-priority lossy traffic
    	# (through $swp2)
	devlink_pool_size_thtype_set 2 static $_1MB

	# Pool 5 is used for egress of paused lossless traffic.
	devlink_pool_size_thtype_set 5 static $_10MB

	# Pool 6 is used for egress of congested traffic.
	devlink_pool_size_thtype_set 6 static $_1_5MB

	# $swp2
	# -----

	ip link set dev $swp2 up
	mtu_set $swp2 10000
	vlan_create $swp2 222
	devlink_port_pool_th_set $swp2 2 $_1MB
	devlink_tc_bind_pool_th_set $swp2 2 ingress 2 $_1MB
	lldptool -T -i $swp2 -V ETS-CFG up2tc=0:6,1:1,2:2,3:3,4:4,5:5,6:6,7:7

	# $swp3
	# -----

	ip link set dev $swp3 up
	mtu_set $swp3 10000
	ethtool -s $swp3 speed 1000 autoneg off
	vlan_create $swp3 111
	vlan_create $swp3 222
	devlink_port_pool_th_set $swp3 6 $_1_5MB
	devlink_tc_bind_pool_th_set $swp3 1 egress 6 $_1_5MB
	devlink_tc_bind_pool_th_set $swp3 2 egress 6 $_1_5MB

	# prio n -> TC n, strict scheduling
	lldptool -T -i $swp3 -V ETS-CFG up2tc=0:6,1:1,2:2,3:3,4:4,5:5,6:6,7:7
	lldptool -T -i $swp3 -V ETS-CFG tsa=$(
			)"7:strict,"$(
			)"6:strict,"$(
			)"5:strict,"$(
			)"4:strict,"$(
			)"3:strict,"$(
			)"2:strict,"$(
			)"1:strict,"$(
			)"0:strict"

	# $swp1
	# -----

	ip link set dev $swp1 up
	mtu_set $swp1 10000
	ethtool -s $swp1 speed 1000 autoneg off
	vlan_create $swp1 111
	devlink_port_pool_th_set $swp1 1 $_500KB
	devlink_tc_bind_pool_th_set $swp1 1 ingress 1 $_500KB

	# Configure PFC. Configure up2tc as well to assign the PFC priority to a
	# dedicated PG, even though the up->tc mapping itself is not useful on
	# $swp1.
	lldptool -T -i $swp1 -V ETS-CFG up2tc=0:0,1:1,2:2,3:3,4:4,5:5,6:6,7:7
	lldptool -T -i $swp1 -V PFC willing=no enableTx=no
	lldptool -T -i $swp1 -V PFC enabled=1 delay=65535

	# bridges
	# -------

	ip link add name br111 up type bridge vlan_filtering 0
	ip link set dev $swp1.111 master br111
	ip link set dev $swp3.111 master br111

	ip link add name br222 up type bridge vlan_filtering 0
	ip link set dev $swp2.222 master br222
	ip link set dev $swp3.222 master br222
}

switch_destroy()
{
	ip link set dev $swp3.222 nomaster
	ip link set dev $swp2.222 nomaster
	ip link del dev br222

	ip link set dev $swp3.111 nomaster
	ip link set dev $swp1.111 nomaster
	ip link del dev br111

	lldptool -T -i $swp1 -V PFC enabled=none
	lldptool -T -i $swp1 -V PFC enableTx=no
	lldptool -T -i $swp1 -V ETS-CFG up2tc=0:0,1:0,2:0,3:0,4:0,5:0,6:0,7:0

	# Do this first so that we can reset the limits to values that are only
	# valid for the original configuration.
	devlink_pool_size_thtype_restore 6
	devlink_pool_size_thtype_restore 5
	devlink_pool_size_thtype_restore 2
	devlink_pool_size_thtype_restore 1
	devlink_pool_size_thtype_restore 4
	devlink_pool_size_thtype_restore 0

	devlink_tc_bind_pool_th_restore $swp1 1 ingress
	devlink_port_pool_th_restore $swp1 1
	vlan_destroy $swp1 111
	ethtool -s $swp1 autoneg on
	mtu_restore $swp1
	ip link set dev $swp1 down

	lldptool -T -i $swp3 -V ETS-CFG up2tc=0:0,1:0,2:0,3:0,4:0,5:0,6:0,7:0

	devlink_tc_bind_pool_th_restore $swp3 1 egress
	devlink_tc_bind_pool_th_restore $swp3 2 egress
	devlink_port_pool_th_restore $swp3 6
	vlan_destroy $swp3 222
	vlan_destroy $swp3 111
	ethtool -s $swp3 autoneg on
	mtu_restore $swp3
	ip link set dev $swp3 down

	devlink_tc_bind_pool_th_restore $swp2 2 ingress
	devlink_port_pool_th_restore $swp2 2
	vlan_destroy $swp2 222
	mtu_restore $swp2
	ip link set dev $swp2 down
}

setup_prepare()
{
	_=${NETIFS[p1]}
	swp1=${NETIFS[p2]}

	swp2=${NETIFS[p3]}
	h2=${NETIFS[p4]}

	swp3=${NETIFS[p5]}
	h3=${NETIFS[p6]}

	h3mac=$(mac_get $h3)

	vrf_prepare

	h2_create
	h3_create
	switch_create
}

cleanup()
{
	pre_cleanup

	switch_destroy
	h3_destroy
	h2_destroy

	vrf_cleanup
}

ping_ipv4()
{
	ping_test $h2 192.0.2.66 " from H2"
}

test_qos_pfc()
{
	start_traffic $h2.222 192.0.2.65 192.0.2.66 $h3mac
	rate_2=($(measure_rate $swp2 $h3 rx_octets_prio_2 "prio 2"))
	check_err $? "Could not get high enough prio-2 ingress rate"

	read -p ready

	stop_traffic # $h2.222
}

trap cleanup EXIT

setup_prepare
setup_wait
sleep 15 # lldpad takes forever to push those configurations

tests_run

exit $EXIT_STATUS
