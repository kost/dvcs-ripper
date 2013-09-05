#!/usr/bin/perl

use strict;

use LWP;
use LWP::UserAgent;
use HTTP::Request;
use Getopt::Long;

my $configfile="$ENV{HOME}/.rip-cvs";
my %config;
$config{'branch'} = "HEAD";
$config{'scmdir'} = "CVS";
$config{'agent'} = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.7; rv:10.0.2) Gecko/20100101 Firefox/10.0.2';
$config{'verbose'}=0;
$config{'checkout'}=1;
$config{'outdir'}='./';
$config{'rlevel'}=9;

if (-e $configfile) {
	open(CONFIG,"<$configfile") or next;
	while (<CONFIG>) {
	    chomp;                  # no newline
	    s/#.*//;                # no comments
	    s/^\s+//;               # no leading white
	    s/\s+$//;               # no trailing white
	    next unless length;     # anything left?
	    my ($var, $value) = split(/\s*=\s*/, $_, 2);
	    $config{$var} = $value;
	} 
	close(CONFIG);
}

Getopt::Long::Configure ("bundling");

my $result = GetOptions (
	"a|agent=s" => \$config{'agent'},
	"b|branch=s" => \$config{'branch'},
	"u|url=s" => \$config{'url'},
	"c|checkout!" => \$config{'checkout'},
	"s|verifyssl!" => \$config{'verifyssl'},
	"v|verbose+"  => \$config{'verbose'},
	"h|help" => \&help
);

my @scmfiles=(
"Repository",
"Root",
"Entries"
);

if ($config{'verbose'}>3) {
	foreach my $key ( keys %config )
	{
	  print "[c] $key => $config{$key}\n";
	}
}

my $ua = LWP::UserAgent->new;
$ua->agent($config{'agent'});

# normalize URL
if ($config{'url'} =~ /\/\CVS/) {
	$config{'scmurl'} = $config{'url'};
	$config{'regurl'} = $config{'url'};
	$config{'regurl'} =~ s/\/CVS//;
} else {
	$config{'scmurl'} = $config{'url'}."/CVS";
	$config{'regurl'} = $config{'url'};
}

processcvs ('',$config{'outdir'},0);

sub processcvs {
	my ($url,$dir,$level) = @_;
	createcvsdirs ($dir);
	downloadcvsfiles ($url,$dir);

	return if ($level>$config{'rlevel'});

	my $cntfile;

	my $ident=" "x$level;

	if (-e "$dir/$config{'scmdir'}/Root" and $level==0) {
		$cntfile++;
		print "$ident"."[i] CVSROOT=";
		displayfile("$dir/$config{'scmdir'}/Root");	
	}

	if (-e "$dir/$config{'scmdir'}/Repository" and $level==0) {
		$cntfile++;
		print "$ident"."[i] cvs checkout ";
		displayfile("$dir/$config{'scmdir'}/Repository");
	}

	if (-e "$dir/$config{'scmdir'}/Entries") {
		$cntfile++;
		my $cont=readfile("$dir/$config{'scmdir'}/Entries");
		# print $cont;
		# print sprintf "%s%1s %-25s %-14s %22s\n", "T", "Name", "Revision", "Date";
		foreach ( split /\n/, $cont ) {
			if (/\//) {
				my @rec = split(/\//);
				print sprintf "%s%1s %-38s %-14s %22s\n", $ident, $rec[0], $rec[1], $rec[2], $rec[3];
				if ($rec[0] eq 'D') {
					mkdir "$dir/$rec[1]";
					processcvs("$url/$rec[1]","$dir/$rec[1]",$level+1);
				}
			}
		}
	}

	if ($level==0) {
		if ($cntfile > 0) {
			print STDERR "$ident"."[i] CVS identified on $config{'url'} by $cntfile guesses\n";
		} else {
			print STDERR "$ident"."[i] CVS not identified, check URL: $config{'url'}\n";
		}
	}

}


sub displayfile {
	my ($file) = @_;
	open (FILE, "<$file") or warn ("cannot open $file: $!");
	while (<FILE>) {
		print $_;
	}
	close (FILE);
}

sub readfile {
	my ($file) = @_;
	open (FILE, "<$file") or warn ("cannot open $file: $!");
	my $str;
	while (<FILE>) {
		$str=$str.$_;
	}
	close (FILE);
	# print ":$str:\n";
	return ($str);
}

sub createcvsdirs {
	my ($dir) = @_;
	mkdir $dir."/CVS";
}

sub downloadcvsfiles {
	my ($url,$dir) = @_;
	foreach my $file (@scmfiles) {
		my $furl = "$url/$config{'scmdir'}/$file";
		getfile($furl,"$dir/$config{'scmdir'}/$file");
	}
}

sub getfile {
	my ($file,$outfile) = @_;
	my $furl = $config{'regurl'}."/".$file;
	my $req = HTTP::Request->new(GET => $furl);
	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);
	if ($res->is_success) {
		print STDERR "[d] found $file\n" if ($config{'verbose'}>1);;
		open (out,">$outfile") or die ("cannot open file '$outfile': $!");
		print out $res->content;
		close (out);
	} else {
		print STDERR "[!] Not found for $furl => $file: ".$res->status_line."\n" 
		if ($config{'verbose'}>1);
	}
	return $res;
}

sub help {
	print "DVCS-Ripper: rip-cvs.pl. Copyright (C) Kost. Distributed under GPL.\n\n";
	print "Usage: $0 [options] -u [url] \n";
	print "\n";
	print " -c	perform 'checkout' on end (default)\n";
	print " -b <s>	Use branch <s> (default: $config{'branch'})\n";
	print " -a <s>	Use agent <s> (default: $config{'agent'})\n";
	print " -s	verify SSL cert\n";
	print " -v	verbose (-vv will be more verbose)\n";
	print "\n";

	print "Example: $0 -v -u http://www.example.com/CVS/\n";
	print "Example: $0 # with url and options in $configfile\n";
	
	exit 0;
}

