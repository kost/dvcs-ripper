#!/usr/bin/perl

use strict;

use LWP;
use DBI;
use LWP::UserAgent;
use HTTP::Request;
use Getopt::Long;

my $configfile="$ENV{HOME}/.rip-svn";
my %config;
$config{'branch'} = "trunk";
$config{'scmdir'} = ".svn";
$config{'agent'} = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.7; rv:10.0.2) Gecko/20100101 Firefox/10.0.2';
$config{'verbose'}=0;
$config{'checkout'}=1;

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
"entries",
"format",
"wc.db"
);

my @commits;
my $ua = LWP::UserAgent->new;
$ua->agent($config{'agent'});

my $gd=$config{'scmdir'}."/";

mkdir $gd;

foreach my $file (@scmfiles) {
	my $furl = $config{'url'}."/".$file;
	getfile($file,$gd.$file);
}

mkdir $gd."pristine";
mkdir $gd."tmp";

if (-e '.svn/wc.db') {
}

my $dbh = DBI->connect("dbi:SQLite:dbname=.svn/wc.db","","");

my $sqlr = 'SELECT id,root,uuid FROM repository';
my $sth = $dbh->prepare($sqlr) or warn "Couldn't prepare statement '$sqlr': " . $dbh->errstr;
$sth->execute();
while (my $record = $sth->fetchrow_hashref()) {
	print "REP INFO => $record->{'id'}:$record->{'root'}:$record->{'uuid'}\n";
}

my $sqlp = "select checksum,compression,md5_checksum from pristine";
my $sthp = $dbh->prepare($sqlp) or warn "Couldn't prepare statement '$sqlp': " . $dbh->errstr;
$sthp->execute();
while (my $record = $sthp->fetchrow_hashref()) {
	print "REC INFO => $record->{'checksum'}:$record->{'compression'}:$record->{'checksum_md5'}\n" if ($config{'verbose'}>1);;
	if ($record->{'checksum'} =~ /\$sha1\$/) {
		my $nfile=substr ($record->{'checksum'},6); 
		getobject($gd,$nfile); 
	} else {
		warn("Unknown checksum: $record->{'checksum'}");
	}
}

$dbh->disconnect;

if ($config{'checkout'}) {
	system("svn revert -R .");
}


sub getobject {
	my ($gd,$ref) = @_;
	my $rdir = substr ($ref,0,2); # first two chars of sha1 is dirname
	my $rfile = $ref.".svn-base"; # whole sha1 is filename
	mkdir $gd."pristine/$rdir";
	getfile("pristine/$rdir/$rfile",$gd."pristine/$rdir/$rfile");
}

sub getfile {
	my ($file,$outfile) = @_;
	my $furl = $config{'url'}."/".$file;
	my $req = HTTP::Request->new(GET => $furl);
	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);
	if ($res->is_success) {
		print STDERR "[d] found $file\n" if ($config{'verbose'}>0);;
		open (out,">$outfile") or die ("cannot open file: $!");
		print out $res->content;
		close (out);
	} else {
		print STDERR "[!] Not found for $file: ".$res->status_line."\n" 
		if ($config{'verbose'}>0);
	}
	return $res;
}

sub help {
	print "DVCS-Ripper: rip-svn.pl. Copyright (C) Kost. Distributed under GPL.\n\n";
	print "Usage: $0 [options] -u [svnurl] \n";
	print "\n";
	print " -c	perform 'checkout' on end (default)\n";
	print " -b <s>	Use branch <s> (default: $config{'branch'})\n";
	print " -a <s>	Use agent <s> (default: $config{'agent'})\n";
	print " -s	verify SSL cert\n";
	print " -v	verbose (-vv will be more verbose)\n";
	print "\n";

	print "Example: $0 -v -u http://www.example.com/.svn/\n";
	print "Example: $0 # with url and options in $configfile\n";
	
	exit 0;
}

