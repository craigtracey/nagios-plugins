#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-29 01:35:11 +0100 (Mon, 29 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check the number of RegionServers that are dead or alive using the HBase Master JSP

Checks the number of dead RegionServers against warning/critical thresholds and lists the dead RegionServers

Recommended to use check_hbase_regionservers.pl instead which uses the HBase Stargate Rest API since parsing the JSP is very brittle and could easily break between versions

Written and tested on CDH 4.3 (HBase 0.94.6-cdh4.3.0)";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;

my $default_port = 60010;
$port = $default_port;

my $default_warning  = 0;
my $default_critical = 0;
$warning  = $default_warning;
$critical = $default_critical;

%options = (
    "H|host=s"         => [ \$host,     "HBase Master to connect to" ],
    "P|port=s"         => [ \$port,     "HBase Master JSP Port to connect to (defaults to $default_port)" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port user password warning critical/;
get_options();

$host       = validate_hostname($host);
$port       = validate_port($port);
my $url = "http://$host:$port/master-status";
vlog_options "url", $url;

validate_thresholds();

vlog2;
set_timeout();

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");
$ua->show_progress(1) if $debug;

$status = "OK";

vlog2 "querying HBase Master JSP";
my $res = $ua->get($url);
vlog2 "got response";
my $status_line  = $res->status_line;
vlog2 "status line: $status_line";
my $content = my $content_single_line = $res->content;
vlog3 "\ncontent:\n\n$content\n";
$content_single_line =~ s/\n/ /g;
vlog2;

unless($res->code eq 200){
    quit "CRITICAL", "'$status_line'";
}
if($content =~ /\A\s*\Z/){
    quit "CRITICAL", "empty body returned from '$url'";
}

my $live_servers_section = 0;
my $dead_servers_section = 0;
my $live_servers;
my $dead_servers;
my @dead_servers;
my $dead_server;
foreach(split("\n", $content)){
    if(/Region Servers/){
        $live_servers_section = 1;
    }
    next unless $live_servers_section;
    if(/<tr><th>Total: <\/th><td>servers: (\d+)<\/td>/){
        $live_servers = $1;
        last;
    }
    last if /<\/table>/;
}
quit "UNKNOWN", "failed to find live server count, JSP format may have changed, try re-running with -vvv, plugin may need updating" unless defined($live_servers);

foreach(split("\n", $content)){
    if(/Dead Region Servers/){
        $dead_servers_section = 1;
    }
    next unless $dead_servers_section;
    if(/<td>([^,]+),\d+,\d+<\/td>/){
        $dead_server = $1;
        push(@dead_servers, $dead_server);
    } elsif(/<tr><th>Total: <\/th><td>servers: (\d+)<\/td><\/tr>/){
        $dead_servers = $1;
        last;
    }
    last if /<\/table>/;
    last if /Regions in Transition/;
}
# This is the best we can do with the JSP unfortunately since it outputs nothing when there are no dead regionservers
defined($dead_servers) or $dead_servers = 0;
#quit "UNKNOWN", "failed to find dead server count, JSP format may have changed, try re-running with -vvv, plugin may need updating" unless defined($dead_servers);

plural $live_servers;
$msg .= "$live_servers live regionserver$plural, ";
plural $dead_servers;
$msg .= "$dead_servers dead regionserver$plural";
check_thresholds($dead_servers);

if(@dead_servers){
    @dead_servers = uniq_array @dead_servers;
    plural scalar @dead_servers;
    $msg .= ". Dead regionserver$plural: " . join(",", @dead_servers);
}
$msg .= " | live_regionservers=$live_servers dead_regionservers=$dead_servers;" . get_upper_thresholds() . ";0";

quit $status, $msg;