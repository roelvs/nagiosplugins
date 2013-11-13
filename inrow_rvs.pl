#!/usr/bin/perl

# check_inrowrc
#
# Scott Nolin - scott.nolin @ ssec.wisc.edu
# 6 June 2010

#monitor APC inrowrc chillers 

use strict;
use warnings;
use Nagios::Plugin;
use Net::SNMP;

use vars qw($verbose $warn $critical $timeout $result);

my $warnpercent=.95; #warn at 95% critical


#use File::Basename;
#$PROGNAME = basename($0);

#########
#prep the plugin and arguments

my $plugin = Nagios::Plugin->new(
	usage => "Usage: %s [-H <HOST>] [-C <community>]",
	blurb => 'This plugin checks the status of an APC inrowrc unit.',
);

#add community string
$plugin->add_arg(
	spec => 'community|C=s',
	help => "SNMP community string",
	required => 1,
);

$plugin->add_arg(
	spec => 'host|H=s',
	help => "hostname",
	required => 1,
);

## parse arguments and process standard
$plugin->getopts;

#define oids
my $oid_powernet393 = '.1.3.6.1.4.1.318.1.1.13'; #base powernet mib
my $oid_thresh_inlet_temp = "$oid_powernet393.4.5.2.4.2.0"; 
my $oid_thresh_supply_temp = "$oid_powernet393.4.5.2.4.4.0"; 
my $oid_thresh_return_temp = "$oid_powernet393.4.5.2.4.6.0"; 
my $oid_thresh_enterfluid_temp = "$oid_powernet393.5.7.0"; 
my $oid_inlet_temp = "$oid_powernet393.4.5.2.1.7.0";#roel aangepast
my $oid_supply_temp = "$oid_powernet393.4.5.2.1.9.0";#roel aangepast
my $oid_return_temp = "$oid_powernet393.4.5.2.1.11.0";#roel aangepast
my $oid_enterfluid_temp = "$oid_powernet393.2.23.0";


my @oids = ($oid_thresh_inlet_temp, $oid_thresh_supply_temp, $oid_thresh_return_temp, $oid_thresh_enterfluid_temp, $oid_inlet_temp, $oid_supply_temp, $oid_return_temp, $oid_enterfluid_temp);


########
#get the data via snmp

my ($session, $session_error) = Net::SNMP->session(
	-hostname => $plugin->opts->host,
	-community => $plugin->opts->community,
	-port	=> 161,
#	-debug => 1,
	-version => 2,
);

if (!defined($session)) { 
        $plugin->nagios_exit(
                return_code => 'WARNING',
                message => "$session_error",
        );
}

my $result = $session->get_request(
	-varbindlist	=> \@oids, 
);

if (!defined($result)) {  
        $plugin->nagios_exit(
                return_code => 'WARNING',
                message => "Error getting SNMP data.",
        );
}

#print results
#check for missing values
my $error=0;
foreach my $oid(@oids) {
	if (!defined($result->{$oid})) {
		$error++;
		print "ERROR: did not get $oid data";
	}
}
if ($error != 0) {  
        $plugin->nagios_exit(
                return_code => 'WARNING',
                message => "Failed to get specific oid",
        );
}

#check thresholds

my $warn=0;

my $inlet = $result->{$oid_inlet_temp}/10;
print ("Inlet:$inlet ");

if ($result->{$oid_inlet_temp} > $result->{$oid_thresh_inlet_temp}){
	print "over threshold! ";
	$error++;
}
elsif ($result->{$oid_inlet_temp} > $warnpercent*$result->{$oid_thresh_inlet_temp}){
	print "approaches threshold! ";
	$warn++;
}

my $supply = $result->{$oid_supply_temp}/10;
print "Supply: $supply ";
	
if ($result->{$oid_supply_temp} > $result->{$oid_thresh_supply_temp}){
	print "exceeds threshold! ";
	$error++;
}
elsif ($result->{$oid_supply_temp} > $warnpercent*$result->{$oid_thresh_supply_temp}){
	print "approaches threshold! ";
	$warn++;
}

my $return = $result->{$oid_return_temp}/10;
print "Return: $return ";
	
if ($result->{$oid_return_temp} > $result->{$oid_thresh_return_temp}){
	print "exceeds threshold! ";
	$error++;
}
elsif ($result->{$oid_return_temp} > $warnpercent*$result->{$oid_thresh_return_temp}){
	print "approaches threshold! ";
	$warn++;
}

my $fluid = $result->{$oid_enterfluid_temp}/10;
print "Fluid Enter: $fluid ";
	
if ($result->{$oid_enterfluid_temp} > $result->{$oid_thresh_enterfluid_temp}){
	print "exceeds threshold! ";
	$error++;
}
elsif ($result->{$oid_enterfluid_temp} > $warnpercent*$result->{$oid_thresh_enterfluid_temp}){
	print "approaches threshold! ";
	$warn++;
}

###add perfdata
$plugin->add_perfdata(
     label => "inlet_temp",
     value => $inlet,
     uom => "c",
#     threshold => "40"
   );

$plugin->add_perfdata(
	label =>"supply_temp",
	value => $supply,
	uom => "c",
);

$plugin->add_perfdata(
	label => "return_temp",
	value => $return,
	uom => "c",
);

	
if ($error != 0) { $plugin->nagios_exit(
	return_code => 'CRITICAL', 
	message => "Errors: $error\n"
	);
}
if ($warn != 0) {  
        $plugin->nagios_exit(
                return_code => 'WARNING',
                message => "Warnings: $warn",
        );
}

#no errors or warnings

$plugin->nagios_exit('OK',"");

print "\n";

