#!/usr/bin/perl
# Clockfort 4/14/2010

# Copyright (c) 2010 Chris Lockfort <clockfort@csh.removethisforspam.rit.edu>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# If you have a problem, just make $DEBUG=1 and it should be fairly apparent 
# where something odd on the network has thrown us for a loop 
# (hopefully not literally) (broadcast storms suck)

use DBI;
use strict;
use warnings;

#Network Settings
my @dynamic_addresses = (140 .. 175);

my $ip_start = "129.21.50";
my $domain = "csh.rit.edu";

#Postgres Settings
my $dbname = "network";
my $host = "db.csh.rit.edu";
my $pg_username = "username";
my $pg_password = "password";

my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host",$pg_username,$pg_password,{RaiseError=>1}) or die "Unable to connect: $DBI::errstr\n";

#File Settings
my $date = get_datestamp();
open(LOG, ">>/var/log/csh/dynamicmon-$date");

my %who_has_ip = ();
my ($warning_month,$warning_day,$warning_hour)=(1337,1337,1337);
my $DEBUG=0;
my $starting_day = get_day();

while(1){
	scan_dynamic_range();
	check_if_running_low();
	exit(0) if $starting_day != get_day();
}

sub hw_addr_to_hostname_and_username{
	my ( $hardware_address, $hostname, $username );
	$hardware_address = shift;
	if($DEBUG){print "in hw_addr_to_hostname_and_username($hardware_address)\n";}
	my $sth = $dbh->prepare("SELECT hostname, username FROM hosts WHERE hardware_address='$hardware_address' ORDER BY username DESC");
	$sth->execute() or die "Crunch! Died while getting hostname from database.";
	$sth->bind_columns( \$hostname, \$username) or die "Bind failed.";
	while ($sth->fetch()){
	}
	$sth->finish();
	return ($hostname, $username);
}

sub scan_dynamic_range{
	foreach my $ip_addr (@dynamic_addresses){
	my $full_ip="$ip_start.$ip_addr";
	my $result = qx(arping -c 1 $full_ip | grep reply);
	my @ret = split("\n",$result);
	if(scalar(@ret)>1){
		print LOG "(!!) Multiple persons responded to $full_ip (!!)\n";
		print "$result\n\n";
	}
	if(defined($ret[0])){
		$result = $ret[0];
	}
	unless($result eq ""){#if someone replied
		if($DEBUG){ print "RESULT PRE-REGEX=$result\n";}
		$result =~ s/^.*\[//;
		$result =~ s/].*//;
		if($DEBUG){print "RESULT POST-REGEX=$result\n";}
		chomp($result);
		if(exists $who_has_ip{$full_ip}){
		unless($who_has_ip{$full_ip} eq $result){
			$who_has_ip{$full_ip}=$result;
			my ($hostname, $username) = hw_addr_to_hostname_and_username($result);
			my $timestamp = get_timestamp();
			print LOG "ALERT: $timestamp New owner: $full_ip is $result, which is $hostname owned by $username.\n";
		}
		}
		else{
			$who_has_ip{$full_ip}=$result;
			my ($hostname, $username) = hw_addr_to_hostname_and_username($result);
			my $timestamp = get_timestamp();
			print LOG "ALERT: $timestamp First seen: $full_ip is $result, which is $hostname owned by $username.\n";
		}
	}
	else{#if no one is home
		if(exists $who_has_ip{$full_ip}){
			unless($who_has_ip{$full_ip} eq ""){
			my ($hostname, $username) = hw_addr_to_hostname_and_username($who_has_ip{$full_ip});
			my $timestamp = get_timestamp();
                	print LOG "ALERT: $timestamp Parted: $full_ip is no longer $who_has_ip{$full_ip}, which was $hostname owned by $username.\n";
			$who_has_ip{$full_ip}=$result;
			}
		}
	}
}
}

sub get_timestamp{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	return sprintf("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
}

sub get_datestamp{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	return sprintf("%4d-%02d-%02d",$year+1900,$mon+1,$mday);
}

sub check_if_running_low{
	if(scalar(keys(%who_has_ip)) == scalar(@dynamic_addresses)){
		my $have_free_ips=0;
		foreach my $key (keys(%who_has_ip)){
		if($who_has_ip{$key} eq ""){$have_free_ips=1;}
		}
		unless($have_free_ips){
			if(once_an_hour()){
				sendmail("devnull\@csh.rit.edu", "Warning: CSHNet Out of Dynamic IPs", "Dwoop! Dwoop! Danger Will Robinson! We've ran out of dynamic IPs!");
			print LOG "Whoops! We're out of IPs!\n";
			}
		}
	}
}


sub once_an_hour{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	if($warning_month == $mon && $warning_day == $mday && $warning_hour == $hour){
		return 0;
	}
	$warning_month=$mon; $warning_day=$mday; $warning_hour=$hour;
	return 1;
}

sub get_day{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	return $mday;
}

sub sendmail{
	my ($to, $subject, $message) = @_;
	my $sendmail = `which sendmail`;
	chomp($sendmail);
	open(MAIL, "| $sendmail -oi -t");
	print MAIL "From: dynamicmon-do-not-reply\@csh.rit.edu\n";
	print MAIL "To: $to\n";
	print MAIL "Subject: $subject\n\n";
	print MAIL "$message\n";
	close(MAIL);
}

sub noob_check(){
	
}
