# check_nutanix_resilience
Plugin to check cluster resilience on Nutanix


You can check the resilience capacity of a nutanix cluster & the effective storage pool usage by choosing the option -o cluster/pool

Usage 
./check_nutanix_resilience.pl [-v] -H <host> -C <snmp_community> [-2] | (-l login -x passwd [-X pass -L <authp>,<privp>])  [-p <port>] -o <pool/cluster> -w <warn level> -c <crit level> [-f] [-t <timeout>] [-V]
