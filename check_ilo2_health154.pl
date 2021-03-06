#!/usr/bin/perl -w
# check_ilo2_health.pl
# based on check_stuff.pl and locfg.pl
#
# Nagios plugin using the Nagios::Plugin module and the
# HP Lights-Out XML PERL Scripting Sample from
# ftp://ftp.hp.com/pub/softlib2/software1/pubsw-linux/p391992567/v60711/linux-LOsamplescripts3.00.0-2.tgz
# checks if all sensors are ok, returns warning on high temperatures and 
# fan failures and critical on overall health failure
#
# Alexander Greiner-Baer <alexander.greiner-baer@web.de> 2007 - 2012
# Matthew Stier <Matthew.Stier@us.fujitsu.com> 2011
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Changelog:
# 1.56    Tue, 12 Mar 2013 20:01:42 +0100
#   applied patches from Dragan Sekerovic <dragan.sekerovic@onestep2.at>:
#     add location label to temperature (option "-b")
#     support for checking event log (option "-l")
#   add 2 new values for power supply status
#   --
# 1.55    Sun, 05 Aug 2012 20:18:46 +0200
#   faulty drive (option "-c") exits now with CRITICAL instead of WARNING
#   applied patches from Niklas Edmundsson <Niklas.Edmundsson@hpc2n.umu.se>:
#     iLO4 RAID Controller Status
#     nodriveexit
#   add g6 drive status
#   overall health probes every element now
#   fixed bug with drive bay index
#   supports iLO3 with multiple backplanes
#   supports iLO4 disk check
#   Note: overall health may show drive/storage status, even without "-c"
#   --
# 1.54    Thu, 14 Jun 2012 21:36:40 +0200
#   applied fix for iLO4 from Niklas Edmundsson <Niklas.Edmundsson@hpc2n.umu.se>
#   --
# 1.53    Tue, 14 Feb 2012 19:47:40 +0100
#   added new disk bay variant
#   added power supply NOT APPLICABLE
#   --
# 1.52    Wed, 27 Jul 2011 20:46:14 +0200
#   fixed <LABEL VALUE = "Power Supplies"/> again
#   --
# 1.51    Mon, 25 Jul 2011 19:36:53 +0200
#   fixed bug with chunked replies by Matthew Stier
#   --
# 1.5     Sat, 16 Jul 2011 10:02:10 +0200
#    optimized by Matthew Stier
#   --
# 1.47    Thu, 14 Jul 2011 12:02:01 +0200
#   also print perfdata when temperature output is disabled
#   --
# 1.46    Wed, 06 Jul 2011 08:46:51 +0200
#   fixed bug with nagios embedded perl interpreter
#   --
# 1.45    Wed, 13 Oct 2010 22:17:01 +0200
#   new option "--ilo3"
#
#   "--checkdrives" enhancements
#
#   <LABEL VALUE = "Power Supplies"/> shows always "Failed" even when the power
#   supplies are redundant 
#
#   improved "--fanredundancy" and "--powerredundancy"
#   --
# 1.44    Mon, 14 Dec 2009 20:11:37 +0100
#   new option "--checkdrives"    
#   --
# 1.43    Mon, 17 Aug 2009 20:50:13 +0200
#   new option "--fanredundancy"
#
#   new option "--powerredundancy"
#   --
# 1.42          Mon, 17 Aug 2009 12:52:23 +0100
#   check power supply and fans redundancy 
#               gcivitella@enter.it
#   --
# 1.41          Thu, 26 Jul 2007 17:42:36 +0200
#   perfdata label ist now quoted
#   --
# 1.4           Mon, 25 Jun 2007 09:45:52 +0200
#   check vrm and power supply
#   
#   new option "--notemperatures"
#   
#   new option "--perfdata"
#   
#   some minor changes
#   --
# 1.3beta       Wed, 20 Jun 2007 09:57:46 +0200
#   do some error checking
#   
#   new option "--inputfile"
#   read bmc output from file
#   --
# 1.2   Mon, 18 Jun 2007 09:33:17 +0200
#   new option "--skipsyntaxerrors"
#   ignores syntax errors in the xml output, maybe required by older firmwares
#   
#   introduce a date to the changelog ;)
#   --
# 1.1   do not return warning if temperature status is n/a
#
#   add "<LOCFG VERSION="2.21" />" to get rid of the
#   "<INFORM>Scripting utility should be updated to the latest version.</INFORM>"
#   message
#   --
# 1     initial release

use strict;
use warnings;
use strict 'refs';

use Nagios::Plugin;
use Sys::Hostname;
use IO::Socket::SSL;
use XML::Simple;

$Net::SSLeay::slowly = 5;

use vars qw($VERSION $PROGNAME  $verbose $warn $critical $timeout $result);
$VERSION = 1.56;

$PROGNAME = "check_ilo2_health";

# instantiate Nagios::Plugin
our $p = Nagios::Plugin->new(
        usage => "Usage: %s [-H <host>] [ -u|--user=<USERNAME> ] 
  [ -p|--password=<PASSWORD> ] [ -f|--inputfile=<filename> ]
  [ -a|--fanredundancy ] [ -c|--checkdrives ] [ -d|--perfdata ] 
  [ -e|--skipsyntaxerrors ] [ -n|--notemperatures ] [ -3|--ilo3 ] 
  [ -o|--powerredundancy ] [ -b|--locationlabel ] [ -l|--eventlogcheck]
  [ -t <timeout>] [ -v|--verbose ] ",
        version => $VERSION,
        blurb => 'This plugin checks the health status on a remote iLO2|3|4 device
and will return OK, WARNING or CRITICAL. iLO (integrated Lights-Out)
can be found on HP Proliant servers.'
);

$p->add_arg(
  spec => 'host|H=s',
  help => 
  qq{-H, --host=STRING
  Specify the host on the command line.},
);

# add all arguments
$p->add_arg(
  spec => 'user|u=s',
  help => 
  qq{-u, --user=STRING
  Specify the username on the command line.},
);

$p->add_arg(
  spec => 'password|p=s',
  help => 
  qq{-p, --password=STRING
  Specify the password on the command line.},
);

$p->add_arg(
  spec => 'inputfile|f=s',
  help => 
  qq{-f, --inputfile=STRING
  Read input from file.},
);

$p->add_arg(
  spec => 'fanredundancy|a',
  help => 
  qq{-a, --fanredundancy
  Check fan redundancy},
);

$p->add_arg(
  spec => 'checkdrives|c',
  help => 
  qq{-c, --checkdrives
  Check drive bays.},
);

$p->add_arg(
  spec => 'perfdata|d',
  help => 
  qq{-d, --perfdata
  Enable perfdata on output.},
);

$p->add_arg(
  spec => 'locationlabel|b',
  help => 
  qq{-b, --locationlabel
  Show temperature with location.},
);

$p->add_arg(
  spec => 'eventlogcheck|l',
  help => 
  qq{-l, --eventlogcheck
  Parse ILO eventlog for interesting events (f.e. broken memory).},
);


$p->add_arg(
  spec => 'skipsyntaxerrors|e',
  help => 
  qq{-e, --skipsyntaxerrors
  Skip syntax errors on older firmwares.},
);

$p->add_arg(
  spec => 'notemperatures|n',
  help => 
  qq{-n, --notemperatures
  Disable temperature listing.},
);

$p->add_arg(
  spec => 'powerredundancy|o',
  help => 
  qq{-o, --powerredundancy
  Check power redundancy.},
);

$p->add_arg(
  spec => 'ilo3|3',
  help => 
  qq{-3, --ilo3
  Check iLO3|4 device.},
);

# parse arguments
$p->getopts;

my $return = "OK";
my $message = "";
our $xmlinput = "";
our $isinput = 0;
our $drive_input = "";
our $is_drive_input = 0;
our $drive_xml_broken = 0;
our $client;
our $is_event_input = 0;
our $event_severity = "";
our $event_class = "";
our $event_description = "";
our %event_status; 
my $host = $p->opts->host;
my $username = $p->opts->user;
my $password = $p->opts->password;
my $inputfile = $p->opts->inputfile;
our $skipsyntaxerrors = defined($p->opts->skipsyntaxerrors) ? 1 : 0;
my $optfanredundancy = defined($p->opts->fanredundancy) ? 1 : 0;
my $optpowerredundancy = defined($p->opts->powerredundancy) ? 1 : 0;
my $notemperatures = defined($p->opts->notemperatures) ? 1 : 0;
our $optcheckdrives = defined($p->opts->checkdrives) ? 1 : 0;
my $optilo3 = defined($p->opts->ilo3) ? 1 : 0;
my $perfdata = defined($p->opts->perfdata) ? 1 : 0;
my $locationlabel = defined($p->opts->locationlabel) ? 1 : 0;
my $eventlogcheck = defined($p->opts->eventlogcheck) ? 1 : 0;
our %drives;
our $drive;
our $drivestatus;

unless ( ( defined($inputfile) ) || 
         ( defined($host) && defined($username) && defined($password) ) ) {
  $p->nagios_die("ERROR: Missing host, password and user.");
}

alarm $p->opts->timeout;

my $boundary;
our $sendsize;
my $localhost = hostname() || 'localhost';
print "hostname is $localhost\n" if ( $p->opts->verbose );

unless ( defined($inputfile) ) {
  # query code from locfg.pl
  # Set the default SSL port number if no port is specified
  $host .= ":443" unless ($host =~ m/:/);
  #
  # Open the SSL connection and the input file
  $client = new IO::Socket::SSL->new(PeerAddr => $host);
  unless ( $client ) {
    $p->nagios_exit(
      return_code => "UNKNOWN",
      message => "ERROR: Failed to establish SSL connection with $host."
    );
  }

  if ( $optilo3 ) {
  print "sending ilo3\n" if ( $p->opts->verbose );
    my $cmd = '<?xml version="1.0"?>';
    $cmd .= '<LOCFG VERSION="2.21" />';
    $cmd .= '<RIBCL VERSION="2.21">';
    $cmd .= '<LOGIN USER_LOGIN="'.$username.'" PASSWORD="'.$password.'">';
    $cmd .= '<SERVER_INFO MODE="read">';
    $cmd .= '<GET_EMBEDDED_HEALTH />';
    if ( $eventlogcheck) { $cmd .= '<GET_EVENT_LOG />'; };
    $cmd .= '</SERVER_INFO>';
    $cmd .= '</LOGIN>';
    $cmd .= '</RIBCL>';
    $cmd .= "\r\n";
    send_or_calculate(0,$cmd);

    send_to_client(0, "POST /ribcl HTTP/1.1\r\n");
    send_to_client(0, "HOST: $localhost\r\n");          # Mandatory for http 1.1
    send_to_client(0, "TE: chunked\r\n");
    send_to_client(0, "Connection: Close\r\n");         # Required
    send_to_client(0, "Content-length: $sendsize\r\n"); # Mandatory for http 1.1
    send_to_client(0, "\r\n");
    send_or_calculate(1,$cmd);  #Send it to iLO
  }
  else {
    # send xml to BMC
    print $client '<?xml version="1.0"?>' . "\r\n";
    print $client '<LOCFG VERSION="2.21" />' . "\r\n";
    print $client '<RIBCL VERSION="2.21">' . "\r\n";
    print $client '<LOGIN USER_LOGIN="'.$username.'" PASSWORD="'.$password.'">' . "\r\n";
    print $client '<SERVER_INFO MODE="read">' . "\r\n";
    print $client '<GET_EMBEDDED_HEALTH />' . "\r\n";
    print $client '</SERVER_INFO>' . "\r\n";
    print $client '</LOGIN>' . "\r\n";
    print $client '</RIBCL>' . "\r\n";
  }
}
else {
  open($client,$inputfile) or $p->nagios_die("ERROR: $inputfile not found");
}

# retrieve data
if ( $optilo3 && !$inputfile ) {
  read_chunked_reply();
}
else {
  while (my $ln = <$client>) {
    parse_reply($ln);
  }
  close $client;
}

# parse with XML::Simple
my $xml;
if ( $xmlinput && $isinput == 0 ) {
  $xml = XMLin($xmlinput, ForceArray => 1);
}
else { 
  $p->nagios_exit(
    return_code => "UNKNOWN",
    message => "ERROR: No parseable output."
  );
}
my $drive_xml;
if ( $optcheckdrives && !$drive_xml_broken ) {
  if ( $drive_input && $is_drive_input == 0 ) {
    $drive_xml = XMLin($drive_input, ForceArray => 1);
  }
  elsif ( ref $xml->{'STORAGE'}[0]->{'CONTROLLER'} ) {
    # iLO4 specific, no need for $drive_input
  }
  else { 
    # No need to error out if host uncapable of checking drive status
    warn "No drive_input found" if ( $p->opts->verbose );
  }
}

my $temperatures = $xml->{'TEMPERATURE'}[0]->{'TEMP'};
my $backplanes = $drive_xml->{'BACKPLANE'};
my $raidcontroller = $xml->{'STORAGE'}[0]->{'CONTROLLER'};
my @checks;
push(@checks,$xml->{'FANS'}[0]->{'FAN'});
push(@checks,$xml->{'VRM'}[0]->{'MODULE'});
push(@checks,$xml->{'POWER_SUPPLIES'}[0]->{'SUPPLY'});
my $health = $xml->{'HEALTH_AT_A_GLANCE'}[0];
my $label;
my $status;
my $temperature;
my $cautiontemp;
my $criticaltemp;

## check overall health status

my $componentstate;
foreach (keys %{$health}) {
  $componentstate = $health->{$_}[0]->{'STATUS'};
  if ( defined($componentstate) && ( $componentstate !~ m/^Ok$|^OTHER$|^NOT APPLICABLE$/i ) ) {
    if($_ eq 'STORAGE') {
      if ( ref($raidcontroller) ) {
       # For iLO4 we can look at the raid controller to get a more detailed
       # status, so just log a WARNING unless we find something CRITICAL
       # later on.
       $return = "WARNING" unless ( $return eq "CRITICAL" );
      }
      else {
       $return = "CRITICAL";
      }
    }
    else {
      $return = "CRITICAL";
    }
    $message .= "$_ $componentstate, ";
  }
}

if ( $optpowerredundancy ) {
  my $powerredundancy = $health->{'POWER_SUPPLIES'}[1]->{'REDUNDANCY'};
  if ( defined($powerredundancy) && 
    ( $powerredundancy !~ m/^Fully Redundant$|^REDUNDANT$|^NOT APPLICABLE$/i ) ) {
    $return = "CRITICAL";
    $message .= "Power supply $powerredundancy, ";
  }
}

if ( $optfanredundancy ) {
  my $fanredundancy = $health->{'FANS'}[1]->{'REDUNDANCY'};
  if ( defined($fanredundancy) && 
    ( $fanredundancy !~ m/^Fully Redundant$|^REDUNDANT$|^NOT APPLICABLE$/i ) ) {
    $return = "CRITICAL";
    $message .= "Fans $fanredundancy, ";
  }
}

# check fans, vrm and power supplies
foreach my $check ( @checks ) {
  if ( ref($check) ) {
    foreach my $item ( @$check ) {
      $label=$item->{'LABEL'}[0]->{'VALUE'};
      $status=$item->{'STATUS'}[0]->{'VALUE'};
      if ( defined($label) && defined($status) ) {
        if ($label =~ m/^Power Supplies$/) {
          next;
        }
        $label =~ s/ /_/g;
        if ( ( $status !~ m"^Ok$|^n/a$|^Not Installed$|^Good, In Use$|^Unknown$"i ) ) {
          $return = "WARNING" unless ( $return eq "CRITICAL" );
          $message .= "$label: $status, ";
        }
      }
    }
  }
}

# check newer drive bays (iLO3)
if ( ref($backplanes) ) {
  foreach ( @{$backplanes} ) {
    if ( $_->{'DRIVE_BAY'} ) {
      for ( my $i=0; $i<= $#{$_->{'DRIVE_BAY'}}; $i++ ) {
        $label=$_->{'DRIVE_BAY'}[$i]->{'VALUE'};
        $status=$_->{'STATUS'}[$i]->{'VALUE'};
        $drives{$label} = $status;
      }
    }
    if ( $_->{'DRIVE'} ) {
      for ( my $i=0; $i<= $#{$_->{'DRIVE'}}; $i++ ) {
        $label=$_->{'DRIVE'}[$i]->{'BAY'};
        $status=$_->{'DRIVE_STATUS'}[$i]->{'VALUE'};
        $drives{$label} = $status;
      }
    }
  }
}

# seems that iLO4 reads the state from the RAID controller, nice
if ( ref($raidcontroller) ) {
  foreach ( @{$raidcontroller} ) {
    my $ctrllabel = $_->{'LABEL'}[0]->{'VALUE'};
    my $ctrlstatus = $_->{'CONTROLLER_STATUS'}[0]->{'VALUE'}; 
    if($ctrlstatus ne 'OK') {
      $return = "CRITICAL";
      $message .= "SmartArray $ctrllabel Status: $ctrlstatus, ";
    }
    my $cachestatus = $_->{'CACHE_MODULE_STATUS'}[0]->{'VALUE'}; 
    if($cachestatus && $cachestatus ne 'OK') {
      # FIXME: There are probably other valid cache module states that
      #        needs to be excluded.
      $return = "CRITICAL";
      $message .= "SmartArray $ctrllabel Cache Status: $cachestatus, ";
    }
    foreach ( @{$_->{'DRIVE_ENCLOSURE'}} ) {
      my $enclabel = $_->{'LABEL'}[0]->{'VALUE'};
      my $encstatus = $_->{'STATUS'}[0]->{'VALUE'};
      if($encstatus ne 'OK') {
              $message .= "SmartArray $ctrllabel Enclosure $enclabel: $encstatus, ";
        $return = "CRITICAL";
      }
    }
    foreach ( @{$_->{'LOGICAL_DRIVE'}} ) {
      my $ldlabel = $_->{'LABEL'}[0]->{'VALUE'};
      my $ldstatus = $_->{'STATUS'}[0]->{'VALUE'};
      if($ldstatus ne 'OK') {
              $message .= "SmartArray $ctrllabel LD $ldlabel: $ldstatus, ";
              if($ldstatus eq 'Degraded (Rebuilding)') {
                $return = "WARNING" unless ( $return eq "CRITICAL" );
              }
              else {
                $return = "CRITICAL";
              }
      }
      foreach ( @{$_->{'PHYSICAL_DRIVE'}} ) {
        $label = "$ctrllabel $_->{'LABEL'}[0]->{'VALUE'}";
        $status = $_->{'STATUS'}[0]->{'VALUE'};
        $drives{$label} = $status;
      }
    }
  }
}

# check drive bays
if ( $optcheckdrives ) {
  foreach ( sort keys(%drives) ) {
    if ( ( $drives{$_} !~ m"^(Ok)$|^(n/a)$|^(Not Installed)|^(Not Present/Not Installed)$"i ) ) {
      $return = "CRITICAL";
      $message .= "Drive Bay $_: ".$drives{$_}.", ";
    }
  }
}

# check event logs
if ( $eventlogcheck ) {
  foreach ( keys %event_status ) {
    next if ( $event_status{$_} =~ m/Repaired/ );
    $message .= "$_:$event_status{$_} ";
    $return = "WARNING" unless ( $return eq "CRITICAL" );
  }
}

unless ( $message ) {
  $message .= "No faults detected, ";
}

# check temperatures
if ( ref($temperatures) ) {
  unless ( $notemperatures ) {
    $message .= "Temperatures: ";
  }
  foreach my $temp ( @$temperatures ) {
    $label=$temp->{'LABEL'}[0]->{'VALUE'};
    if ( $locationlabel && defined($temp->{'LOCATION'}[0]->{'VALUE'}) ) {
      $label .= " (" . $temp->{'LOCATION'}[0]->{'VALUE'} . ")";
    }
    $status=$temp->{'STATUS'}[0]->{'VALUE'};
    $temperature=$temp->{'CURRENTREADING'}[0]->{'VALUE'};
    if ( defined($label) && defined($status) && defined($temperature) ) {
      $label =~ s/ /_/g;
      unless ( ( $status =~ m"^Ok$|^n/a$|^Not Installed$"i ) ) {
        $return = "WARNING" unless ( $return eq "CRITICAL" );
        $message .= "$label ($status): $temperature, " 
          if ( $notemperatures );
      }
      unless ( ( $status =~ m"^n/a$|^Not Installed$"i ) )  {
        $message .= "$label ($status): $temperature, " 
          unless ( $notemperatures );
        if ( $perfdata ) {
          $cautiontemp=$temp->{'CAUTION'}[0]->{'VALUE'};
          $criticaltemp=$temp->{'CRITICAL'}[0]->{'VALUE'};
          # Returned value can be 'N/A', enforce this being a number
          if($cautiontemp && $cautiontemp !~ /^[0-9]+/) {
                $cautiontemp=undef;
          }
          if($criticaltemp && $criticaltemp !~ /^[0-9]+/) {
                $criticaltemp=undef;
          }
          if ( defined($cautiontemp) && defined($criticaltemp) ) {
            $p->set_thresholds(
              warning  => $cautiontemp,
              critical => $criticaltemp,
            );
            my $threshold = $p->threshold;
            # add perfdata
            $p->add_perfdata(
              label   => $label,
              value   => $temperature,
              uom     => "",
              threshold => $threshold,
            );
          }
        }
      }
    }
    else {
      $message .= "no reading, ";
    }
  }
}


# strip trailing ","
$message =~ s/, $//;

$p->nagios_exit( 
  return_code => $return, 
  message => $message 
);


# send_to_client, send_or_calculate and read_chunked_reply 
# are adapted from locfg.pl

sub send_to_client
{
  my ($send, $cmd) = @_;
  print $cmd if ( $p->opts->verbose && length($cmd) < 1024 );
  print $client $cmd;
  $sendsize -= length($cmd) if ( $send );
}

sub send_or_calculate    # used for iLO 3 only
{
  $sendsize = 0;
  my ($send, $cmd) = @_;
  if ($send) {
    print $client $cmd;
  }
  $sendsize += length($cmd);
  print "size $sendsize\n" if ( $p->opts->verbose );
}


sub read_chunked_reply    # used for iLO 3 only
{
  my $ln = "";
  my $lp = "";
  my $hide = 1;
  my $chunk = 1;
  my $chunkSize;

  while( 1 ) {
    # Read a line
    $ln = <$client>;
    # Get length of line
    my $length =  length($ln);
    # Exit loop if zero
    if ( $length == 0 ) {
      if ( $verbose ) {
        print "read_chunked_reply: read a zero-length line. Continue...\n";
      }
      last;
    }
    # Skip HTTP headers and first line of chunked responses
    if ( $hide ) {
        $hide = 0 if ( $ln =~ m/^\r\n$/ );
        print $ln if ( $verbose );
        next;
    }
    # Get size of chunk
    if ( $chunk ) {
      $ln =~ s/\r\n$//; 
      $chunkSize = hex($ln);
      $chunk = 0;
      print $chunkSize if ( $verbose );
      next;
    }
    # Last Chunk
    if ( $chunkSize == 0 ) {
      print "read_chunked_reply: reach end of responses.\n" if ($verbose);
      last;
    }
    # End of chunk, process incomplete line
    if ( $chunkSize < $length ) {
      $chunk = 1; # Next line, new chunk
      $hide = 0;  # Skip hide
      $lp .= substr($ln, 0, $chunkSize); # Truncate and append
    }
    # End of chunk, process complete line
    elsif ( $chunkSize == $length ) {
      $chunk = 1; # Next line, new chunk
      $hide = 1;  # Hide new chunk's first line
      $lp .= $ln; # Append line as-is
    }
    # Process line
    else {
      $chunkSize -= $length; # Decrement chunk size
      $lp .= $ln; # Append line as-is
    }
    # Skip incomplete line
    next unless ( $lp =~ m/\n$/ ); 
    # Parse complete line
    parse_reply($lp);
    # Line parsed, clear line
    $lp = "";
  }
  if ($client->error()) {
     print "Error: connection error " . $client->error() . "\n";
  }
}

sub parse_reply
{
  my ($line) = @_;
  $line =~ s/\r\n$/\n/;
  print $line if ( $p->opts->verbose );

  # Prune all unnecessary lines
  $isinput = 1 if ( $line =~ m"<GET_EMBEDDED_HEALTH_DATA>|</DRIVES>" );
  $xmlinput .= $line if ( $isinput );
  $isinput = 0 if ( $line =~ m"</GET_EMBEDDED_HEALTH_DATA>|<DRIVES>" );

  # drive check needs special handling
  # <DRIVES>
  #    <BACKPLANE>
  #       <FIRMWARE_VERSION VALUE="1.18"/>
  #       <ENCLOSURE_ADDR VALUE="224"/>
  #     <DRIVE_BAY VALUE = "1"/>
  #       <PRODUCT_ID VALUE = "EH0300FBQDD    "/>
  #       <STATUS VALUE = "Ok"/>
  #       <UID_LED VALUE = "Off"/>
  #     <DRIVE_BAY VALUE = "2"/>
  #       <PRODUCT_ID VALUE = "EH0300FBQDD    "/>
  #       <STATUS VALUE = "Fault"/>
  #       <UID_LED VALUE = "Off"/>
  #    </BACKPLANE>
  # </DRIVES>

  $is_drive_input = 1 if ( $line =~ m"<DRIVES>" );
  $drive_input .= $line if ( $is_drive_input );
  $is_drive_input = 0 if ( $line =~ m"</DRIVES>" );

  # because on many (older?) iLOs drive status is not XML
  if ($optcheckdrives) {
    if ( $line =~ m/<Drive Bay: / ) {
      $drive_xml_broken = 1;
      # <Drive Bay: "3"; status: "Smart Error"; uid led="Off"/>
      ( $drive, $drivestatus ) = ( $line =~ 
        m/Drive Bay: "(.*)"; status: "(.*)"; uid led: ".*"/ );
      if ( defined($drive) && defined($drivestatus) ) {
        $drives{$drive} = $drivestatus;
      }
    }
    if ( $line =~ m/<DRIVE BAY=".*" PRODUCT_ID="/ ) {
      $drive_xml_broken = 1;
      # <DRIVE BAY="3" PRODUCT_ID="N/A"STATUS="Smart Error" UID_LED="Off"/>
      ( $drive, $drivestatus ) = ( $line =~ 
        m/DRIVE BAY="(.*)" PRODUCT_ID=".*"STATUS="(.*)" UID_LED=".*"/ );
      if ( defined($drive) && defined($drivestatus) ) {
        $drives{$drive} = $drivestatus;
      }
    }
  }

  if ( $eventlogcheck ) {
    $is_event_input = 1 if ( $line =~ m"<EVENT" );
    if ( $is_event_input ) {
      if ( $line =~ m/SEVERITY="(.*?)"/ ) {
        $event_severity = $1;
        #print "SEV: $event_severity\n";
      } 
      if ( $line =~ m/CLASS="(.*?)"/ ) {
        $event_class = $1;
        #print "CLASS: $event_class\n";
      }
      if ( $line =~ m/DESCRIPTION="(.*?)"/ ) {
        $event_description = $1;
        #print "DESCRIPTION: $event_description\n";
      }
    }
    $is_event_input = 0 if ( $is_event_input && $line =~ m"/>" );
    if ( $is_event_input == 0 && $event_class ) {
      if ( $event_class !~ m/POST|Maintenance/ ) {
        $event_status{$event_description} = $event_severity;
        $event_class = "";
      }
    }
  }

  if ( $line =~ m/MESSAGE='(.*)'/ ) {
    my $msg = $1;

    if ( $msg =~ m/No error/i ) {
      # Skip
    }
    elsif ( $msg =~ m/Syntax error/i && $skipsyntaxerrors ) {
      # Skip
    }
    else {
      close $client;
      $p->nagios_exit(
        return_code => "UNKNOWN",
        message => "ERROR: $msg."
      );
    }
  }
}
