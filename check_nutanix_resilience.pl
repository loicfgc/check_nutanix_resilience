#!/usr/bin/perl -w 
############################## check_nutanix_axians.pl #################
my $Version='0.8';
# Date    : Jun 30 2021
# Purpose : Nagios plugin used to check nutanix storage pool usage and ensure cluster resiliency capacity.\n";
# Author  : Loïc Fregeac, loic.fregeac@axians.com
#################################################################
#
# Help : ./check_nutanix_axians.pl -h
#


use strict;
use Net::SNMP 5.0;
use Getopt::Long;
use Date::Format;

# Nagios specific

my $TIMEOUT = 15;
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);

# OID data from the NUTANIX-MIB.TXT
my $clusterTotalStorageCapacity   = '1.3.6.1.4.1.41263.504';
my $clusterUsedStorageCapacity    = '1.3.6.1.4.1.41263.505';
my $poolSpitTotalCapacity         = '1.3.6.1.4.1.41263.7.1.4';
my $poolSpitUsedCapacity          = '1.3.6.1.4.1.41263.7.1.5';


# Globals
my $o_host          = 	undef; 		# hostname
my $o_community     =   undef; 	    # community
my $o_port          = 	161; 		# port
my $o_help          =	undef; 		# wan't some help ?
my $o_verb          =	undef;		# verbose mode
my $o_version       =	undef;		# print version
# End compatibility
my $o_option        =	0;		    # remote TZ offset in mins
my $o_warn          =	undef;		# warning level in seconds
my $o_crit          =	undef;		# critical level in seconds
my $o_timeout       =   undef; 		# Timeout (Default 5)
my $o_perf          =   undef;      # Output performance data
my $o_version2      =   undef;      # use snmp v2c -- not allowed on NUTANIX by CNES
# SNMPv3 specific
my $o_login         =	undef;		# Login for snmpv3
my $o_passwd        =	undef;		# Pass for snmpv3
my $v3protocols     =   undef;	    # V3 protocol list.
my $o_authproto     =   'md5';		# Auth protocol
my $o_privproto     =   'des';		# Priv protocol
my $o_privpass      =   undef;		# priv password

# functions
sub p_version { print "check_nutanix_axians version : $Version\n"; }

sub print_usage {
    print "Usage: $0 [-v] -H <host> -C <snmp_community> [-2] | (-l login -x passwd [-X pass -L <authp>,<privp>])  [-p <port>] -o <pool/cluster> -w <warn level> -c <crit level> [-f] [-t <timeout>] [-V]\n";
}

sub isnnum { # Return true if arg is not a number
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$|^-(\d+\.?\d*)|(^-\.\d+)$/ ) { return 0 ;}
  return 1;
}

sub help {
   print "\nSNMP remote to check cluster and Storage pool used capacity ",$Version,"\n";
   print_usage();
   print <<EOT;
This plugin is made for a specific need, it is able to retrieve data on storage pool utilisation or determining if a cluster is resiliant
-v, --verbose
   print extra debugging information 
-h, --help
   print this help message
-H, --hostname=HOST
   name or IP address of host of the cluster
-C, --community=COMMUNITY NAME
   community name for the host's SNMP agent (implies v1 protocol)
-2, --v2c
   Use snmp v2c
-l, --login=LOGIN ; -x, --passwd=PASSWD
   Login and auth password for snmpv3 authentication 
   If no priv password exists, implies AuthNoPriv 
-X, --privpass=PASSWD
   Priv password for snmpv3 (AuthPriv protocol)
-L, --protocols=<authproto>,<privproto>
   <authproto> : Authentication protocol (md5|sha : default md5)
   <privproto> : Priv protocole (des|aes : default des) 
-P, --port=PORT
   SNMP port (Default 161)
-o, --option=pool | cluster
   use pool to check storage pool usage, use cluster to check cluster data resiliency capacity
-w, --warn=INTEGER
   warning level in percentage of the max value
-c, --crit=INTEGER
   critical level in percentage of the max value
-f, --perfparse
   Perfparse compatible output
-t, --timeout=INTEGER
   timeout for SNMP in seconds (Default: 5)
-V, --version
   prints version number
EOT
}

# For verbose output
sub verb { my $t=shift; print $t,"\n" if defined($o_verb) ; }

sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
   	'v'	    => \$o_verb,		'verbose'	    => \$o_verb,
    'h'     => \$o_help,    	'help'        	=> \$o_help,
    'H:s'   => \$o_host,		'hostname:s'	=> \$o_host,
    'p:i'   => \$o_port,   		'port:i'	    => \$o_port,
    'C:s'   => \$o_community,	'community:s'	=> \$o_community,
	'l:s'	=> \$o_login,		'login:s'	    => \$o_login,
	'x:s'	=> \$o_passwd,		'passwd:s'	    => \$o_passwd,
	'X:s'	=> \$o_privpass,	'privpass:s'	=> \$o_privpass,
	'L:s'	=> \$v3protocols,	'protocols:s'	=> \$v3protocols,   
    't:i'   => \$o_timeout,     'timeout:i'     => \$o_timeout,
	'V'	    => \$o_version,		'version'	    => \$o_version,
	'2'     => \$o_version2,    'v2c'           => \$o_version2,
    'c:s'   => \$o_crit,        'critical:s'    => \$o_crit,
    'w:s'   => \$o_warn,        'warn:s'        => \$o_warn,
    'o:s'   => \$o_option,      'option:s'      => \$o_option,
    'f'     => \$o_perf,        'perfparse'     => \$o_perf,
    
	);
    # Basic checks
    if (defined($o_timeout) && (isnnum($o_timeout) || ($o_timeout < 2) || ($o_timeout > 60))) 
      { print "Timeout must be >1 and <60 !\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
    if (!defined($o_timeout)) {$o_timeout=5;}
    if (defined ($o_help) ) { help(); exit $ERRORS{"UNKNOWN"}};
    if (defined($o_version)) { p_version(); exit $ERRORS{"UNKNOWN"}};
    if ( ! defined($o_host) ) # check host and filter 
      { print_usage(); exit $ERRORS{"UNKNOWN"}}
    # check snmp information
    if ( !defined($o_community) && (!defined($o_login) || !defined($o_passwd)) )
	  { print "Put snmp login info!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
    if ((defined($o_login) || defined($o_passwd)) && (defined($o_community) || defined($o_version2)) )
	  { print "Can't mix snmp v1,2c,3 protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
    if (defined ($v3protocols)) {
    if (!defined($o_login)) { print "Put snmp V3 login info with protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
      my @v3proto=split(/,/,$v3protocols);
    if ((defined ($v3proto[0])) && ($v3proto[0] ne "")) {$o_authproto=$v3proto[0];	}	# Auth protocol
    if (defined ($v3proto[1])) {$o_privproto=$v3proto[1];	}	# Priv  protocol
    if ((defined ($v3proto[1])) && (!defined($o_privpass))) {
        print "Put snmp V3 priv login info with priv protocols!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
    }
    # Check option is defined
    if (!defined($o_option)) 
      { print "Option should be pool or cluster\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
    # Check warnings and critical
    if (!defined($o_warn) || !defined($o_crit))
 	{ print "put warning and critical info!\n"; print_usage(); exit $ERRORS{"UNKNOWN"}}
    # Get rid of % sign
    $o_warn =~ s/\%//g; 
    $o_crit =~ s/\%//g;
    if ( isnnum($o_warn) || isnnum($o_crit) ) 
		{ print "Numeric value for warning or critical !\n";print_usage(); exit $ERRORS{"UNKNOWN"}}
    if ($o_warn > $o_crit) 
            { print "warning <= critical ! \n";print_usage(); exit $ERRORS{"UNKNOWN"}}
}

########## MAIN #######
check_options();

# Check gobal timeout if snmp screws up
if (defined($TIMEOUT)) {
  verb("Alarm at $TIMEOUT + 5");
  alarm($TIMEOUT+5);
} else {
  verb("no global timeout defined : $o_timeout + 10");
  alarm ($o_timeout+10);
}

$SIG{'ALRM'} = sub {
 print "No answer from host\n";
 exit $ERRORS{"UNKNOWN"};
};

# Connect to host
my ($session,$error);
if ( defined($o_login) && defined($o_passwd)) {
  # SNMPv3 login
  verb("SNMPv3 login");
    if (!defined ($o_privpass)) {
  verb("SNMPv3 AuthNoPriv login : $o_login, $o_authproto");
    ($session, $error) = Net::SNMP->session(
      -hostname   	=> $o_host,
      -version		=> '3',
      -username		=> $o_login,
      -authpassword	=> $o_passwd,
      -authprotocol	=> $o_authproto,
      -translate    => 0,
      -timeout      => $o_timeout
    );  
  } else {
    verb("SNMPv3 AuthPriv login : $o_login, $o_authproto, $o_privproto");
    ($session, $error) = Net::SNMP->session(
      -hostname   	    => $o_host,
      -version		    => '3',
      -username		    => $o_login,
      -authpassword	    => $o_passwd,
      -authprotocol	    => $o_authproto,
      -privpassword	    => $o_privpass,
      -privprotocol     => $o_privproto,
      -translate        => 0,
      -timeout          => $o_timeout
    );
  }
} else {
    if (defined ($o_version2)) {
        # SNMPv2 Login
        verb("SNMP v2c login");
          ($session, $error) = Net::SNMP->session(
         -hostname  => $o_host,
         -version   => 2,
         -community => $o_community,
         -port      => $o_port,
         -translate => 0,
         -timeout   => $o_timeout
        );
      } else {
      # SNMPV1 login
      verb("SNMP v1 login");
      ($session, $error) = Net::SNMP->session(
        -hostname  => $o_host,
        -community => $o_community,
        -port      => $o_port,
        -translate => 0,
        -timeout   => $o_timeout
      );
    }
}
if (!defined($session)) {
   printf("ERROR opening session: %s.\n", $error);
   exit $ERRORS{"UNKNOWN"};
}

my $exit_val=undef;

############## Start SNMP data retrieve ################

my $finalPoolUsedCapacity;
my $finalPoolTotalCapacity;

if ($o_option =~ m/pool/) {
    my $poolUsedCapacity = $session->get_request(-varbindlist => [$poolSpitUsedCapacity],);

    if (!defined($poolUsedCapacity)) {
        printf("ERROR: Description table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{"UNKNOWN"};
    }

    if (!defined ($$poolUsedCapacity{$poolSpitUsedCapacity})) {
        print "No storage pool usage data : UNKNOWN\n";
        exit $ERRORS{"UNKNOWN"};
    }

    my $poolTotalCapacity = $session->get_request(-varbindlist => [$poolSpitTotalCapacity],);

    if (!defined($poolTotalCapacity)) {
        printf("ERROR: Description table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{"UNKNOWN"};
    }  

    if (!defined ($$poolTotalCapacity{$poolSpitTotalCapacity})) {
        print "No Storage pool capacity data : UNKNOWN\n";
        exit $ERRORS{"UNKNOWN"};
    }   

    $finalPoolUsedCapacity  = $poolUsedCapacity->{$poolSpitUsedCapacity};
    $finalPoolTotalCapacity = $poolTotalCapacity->{$poolSpitTotalCapacity};
}

my $finalclusterTotalCapacity;
my $finalclusterUsedCapacity;

if ($o_option =~ m/cluster/) {
    my $clusterTotalCapacity = $session->get_request(-varbindlist => [$clusterTotalStorageCapacity],);

    if (!defined($clusterTotalCapacity)) {
        printf("ERROR: Description table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{"UNKNOWN"};
    }

    if (!defined ($$clusterTotalCapacity{$clusterTotalStorageCapacity})) {
        print "No cluster capacity data : UNKNOWN\n";
        exit $ERRORS{"UNKNOWN"};
    }

    my $clusterUsedCapacity = $session->get_request(-varbindlist => [$clusterUsedStorageCapacity],);

    if (!defined($clusterUsedCapacity)) {
        printf("ERROR: Description table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{"UNKNOWN"};
    }  

    if (!defined ($$clusterUsedCapacity{$clusterUsedStorageCapacity})) {
        print "No cluster usage data  : UNKNOWN\n";
        exit $ERRORS{"UNKNOWN"};
    }   

    $finalclusterTotalCapacity  = $clusterTotalCapacity->{$clusterTotalStorageCapacity};
    $finalclusterUsedCapacity   = $clusterUsedCapacity->{$clusterUsedStorageCapacity};
}

$session->close;

my $clusterPercentUsed;

if ($o_option =~ m/cluster/) {
    my $clusterFreeCapacity = $finalclusterTotalCapacity - $finalclusterUsedCapacity ;
    $clusterPercentUsed = ($finalclusterUsedCapacity / $clusterFreeCapacity * 100);

    $exit_val=$ERRORS{"OK"};
    if ( $clusterPercentUsed > $o_crit ) {
        print "CRITICAL: Cluster resilience not satisfied: used capacity $clusterPercentUsed";
        $exit_val=$ERRORS{"CRITICAL"};
    }
    if ( $clusterPercentUsed > $o_warn ) {
    # output warn error only if no critical was found
        if ($exit_val eq $ERRORS{"OK"}) {
            print "WARNING: Cluster resilience limited: used capacity $clusterPercentUsed"; 
            $exit_val=$ERRORS{"WARNING"};
        }
    }
    print " : OK" if ($exit_val eq $ERRORS{"OK"});
        if (defined($o_perf)) {
        print " | clusterUsagePercent=$clusterPercentUsed";
    }
    print "\n";

    #data out  print
    printf "-------------------------------";
    printf "finalclusterTotalCapacity = $finalclusterTotalCapacity | finalclusterUsedCapacity = $finalclusterUsedCapacity ";
    printf "clusterUsagePercent = $clusterPercentUsed | clusterFreeCapacity = $clusterFreeCapacity ";
    printf "-------------------------------";
}


my $poolPercentUsed;

if ($o_option =~ m/pool/) {
    my $poolFreeCapacity = $finalPoolTotalCapacity - $finalPoolUsedCapacity;
    $poolPercentUsed = ($finalPoolUsedCapacity / $poolFreeCapacity * 100);

    $exit_val=$ERRORS{"OK"};
    if ( $poolPercentUsed > $o_crit ) {
        print "CRITICAL: Storage pool capaciy usage is hight: used capacity $poolPercentUsed";
        $exit_val=$ERRORS{"CRITICAL"};
    }
    if ( $poolPercentUsed > $o_warn ) {
    # output warn error only if no critical was found
        if ($exit_val eq $ERRORS{"OK"}) {
            print "WARNING: Storage pool usage is warning: used capacity $poolPercentUsed"; 
            $exit_val=$ERRORS{"WARNING"};
        }
    }

    print " : OK" if ($exit_val eq $ERRORS{"OK"});

    if (defined($o_perf)) {
        print " | poolUsagePercent=$poolPercentUsed";
    }
    print "\n";

    printf "-------------------------------";
    printf "finalPoolTotalCapacity = $finalPoolTotalCapacity | finalPoolUsedCapacity = $finalPoolUsedCapacity ";
    printf "poolPercentUsed = $poolPercentUsed | poolFreeCapacity = $poolFreeCapacity ";
    printf "-------------------------------";
}




exit $exit_val;