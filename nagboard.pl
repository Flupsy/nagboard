#!/usr/bin/perl
#
# A status scoreboard for Nagios.
#
# Ian Chard <ian@chard.org>  8/12/2011
#
# Copyright (c) 2005-2013 Ian Chard
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

use strict;
use warnings;

use DBI;
use CGI::Pretty qw/:all/;
use CGI::Cookie;
use Data::Dumper;

my @host_states=('ok', 'down', 'unreachable', 'unknown');
my @service_states=('ok', 'warning', 'critical', 'unknown');

# Obviously this bit will need to be customised for your mrtg (or whatever).
# Graphs are displayed in pairs when there are no alarms.

my %graphs=(
#	'OO-RSL trunk'		=> 'https://my.server/mrtg/10.2.0.251_g1-day.png',
#	'RSL public network'	=> 'https://my.server/mrtg/10.2.0.251-public-day.png',

#	'Osney machine room temperature' => 'https://my.server/mrtg/oo-temp-day.png',
#	'Osney line voltage'	=> 'https://my.server/mrtg/oo-voltage-day.png'
);

# Database connection details for the ndoutils database.

my $dsn='DBI:mysql:database=ndoutils;host=localhost';
my $dbuser='ndo';
my $dbpass='ndo';

my @down_hosts;
my @t;
my $alarms=0;
my $graphpage=0;


sub error($)
{
	print p({-class=>'down'}, $_[0]);
	exit 1;
}

sub plural($) { return ($_[0]==1? '':'s') };

sub is_blinking($)
{
	my $lastchange=$_[0];

	return (time-$lastchange<300)? 'blinking':'moinking';
}

sub is_new($)
{
	my $lastchange=$_[0];

	return (time-$lastchange<300)? 'new':'';
}

sub status_string($$$)
{
	my ($status, $lastchange, $flapping)=@_;
	my $result;

	my $now=time;

	if($now%8<4)
	{
		my $age=$now-$lastchange;

		if($age<60)
		{
			$result="+$age sec".plural($age);
		}
		elsif($age<3600)
		{
			$age=int($age/60);
			$result="+$age min".plural($age);
		}
		elsif($age<172800)
		{
			$age=int($age/3600);
			$result="+$age hr".plural($age);
		}
		else
		{
			$age=int($age/86400);
			$result="+$age day".plural($age)."!";
		}
	}
	else
	{
		$result=$flapping? 'flapping':$status;
	}

	return $result;
}


### PROGRAM ENTRY POINT ###

my $dbh=DBI->connect($dsn, $dbuser, $dbpass, {'RaiseError' => 1});

my $starttime_query=$dbh->prepare("select UNIX_TIMESTAMP(status_update_time) as status_update_time, is_currently_running from nagios_programstatus");

my $hosts_query=$dbh->prepare("select display_name, current_state, output, problem_has_been_acknowledged, UNIX_TIMESTAMP(last_hard_state_change) as last_hard_state_change, current_check_attempt, s.max_check_attempts as max_check_attempts, s.scheduled_downtime_depth from nagios_objects, nagios_hosts as h, nagios_hoststatus as s where objecttype_id=1 and object_id=h.host_object_id and h.host_object_id=s.host_object_id");

my $svcs_query=$dbh->prepare("select h.display_name as hostname, svcs.display_name, svcsstat.current_state, svcsstat.output as output, svcsstat.problem_has_been_acknowledged as problem_has_been_acknowledged, svcsstat.is_flapping as flapping, UNIX_TIMESTAMP(svcsstat.last_hard_state_change) as last_hard_state_change, svcsstat.current_check_attempt as current_check_attempt, svcsstat.max_check_attempts as max_check_attempts, svcsstat.scheduled_downtime_depth from nagios_objects, nagios_hosts as h, nagios_services as svcs, nagios_hoststatus as hoststat, nagios_servicestatus as svcsstat where objecttype_id=2 and object_id=svcs.service_object_id and svcs.service_object_id=svcsstat.service_object_id and svcs.host_object_id=h.host_object_id and svcs.host_object_id=hoststat.host_object_id");

my $hostgroup_query=$dbh->prepare("select h.display_name, group_concat(name1 separator ' ') from nagios_hosts as h, nagios_hostgroup_members as memb, nagios_hostgroups as g, nagios_objects where objecttype_id=3 and object_id=hostgroup_object_id and memb.hostgroup_id=g.hostgroup_id and memb.host_object_id=h.host_object_id group by h.display_name");

my $servicegroup_query=$dbh->prepare("select h.display_name, svcs.display_name, group_concat(name1 separator ' ') from nagios_hosts as h, nagios_servicegroup_members as memb, nagios_servicegroups as g, nagios_objects, nagios_services as svcs where objecttype_id=4 and object_id=servicegroup_object_id and memb.servicegroup_id=g.servicegroup_id and memb.service_object_id=svcs.service_object_id and svcs.host_object_id=h.host_object_id group by h.display_name, svcs.display_name");


my %cookies=CGI::Cookie->fetch;
my $cookie;

if(!defined $cookies{'graphpage'})
{
	$graphpage=0;
}
else
{
	$graphpage=$cookies{'graphpage'}->value;
}

if(time%8==0)
{
	$graphpage=($graphpage+1)%(int((scalar keys %graphs)/2));
	$cookie=CGI::Cookie->new(-name=>'graphpage', -value=>$graphpage);
}

print header(-expires=>'now', -cookie=>[$cookie]);

$starttime_query->execute || error DBI::err.": ".$DBI::errstr;
my $i=$starttime_query->fetchrow_hashref();

error "Nagios is not running." if($$i{'is_currently_running'}!=1);

my $updated_seconds_ago=time-$$i{'status_update_time'};
error "Nagios not updated for $updated_seconds_ago seconds" if($updated_seconds_ago>60);

$hosts_query->execute || error DBI::err.": ".$DBI::errstr;
while(my $i=$hosts_query->fetchrow_hashref())
{
	if($$i{'current_state'}!=0 && $$i{'current_check_attempt'}==$$i{'max_check_attempts'})
	{
		if(!$$i{'problem_has_been_acknowledged'})
		{
			push @t, Tr(td({-name=>is_blinking($$i{'last_hard_state_change'}), -class=>is_new($$i{'last_hard_state_change'}).'down'}, [$$i{'display_name'},
				status_string($host_states[$$i{'current_state'}], $$i{'last_hard_state_change'}, 0)]));
			push @t, Tr(td({-class=>is_new($$i{'last_hard_state_change'}).'downoutput'}, [$$i{'output'}]));
			$alarms++;
		}

		push @down_hosts, $$i{'display_name'};	
	}
}

$svcs_query->execute || error DBI::err.": ".$DBI::errstr;
while(my $i=$svcs_query->fetchrow_hashref())
{
	if($$i{'current_state'}!=0 && !grep(/^$$i{'hostname'}$/, @down_hosts) && $$i{'current_check_attempt'}==$$i{'max_check_attempts'})
	{
		if(!$$i{'problem_has_been_acknowledged'})
		{
			push @t, Tr(td({-name=>is_blinking($$i{'last_hard_state_change'}), -class=>is_new($$i{'last_hard_state_change'}).'notdown'}, [$$i{'hostname'}.':'.$$i{'display_name'},
				status_string($service_states[$$i{'current_state'}], $$i{'last_hard_state_change'}, $$i{'flapping'})]));
			push @t, Tr(td({-class=>is_new($$i{'last_hard_state_change'}).'output'}, [$$i{'output'}]));
			$alarms++;
		}
	}
}

if($alarms)
{
	print table({-width=>'100%'}, @t);

	my @time=localtime;
	print div({-id=>'statusline'}, "$alarms alarm".plural($alarms));
}
else
{
	for($i=$graphpage*2; $i<=($graphpage*2)+1; $i++)
	{
		my $graph=(keys %graphs)[$i];

		print p({-class=>'graphtext'}, $graph);
		print img({-src=>$graphs{$graph}, -width=>'100%'});
	}
}
