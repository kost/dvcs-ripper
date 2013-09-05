#!/usr/bin/perl

use strict;

use LWP;
use LWP::UserAgent;
use HTTP::Request;
use Getopt::Long;

my $configfile="$ENV{HOME}/.rip-git";
my %config;
$config{'branch'} = "master";
$config{'gitdir'} = ".git";
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

my @gitfiles=(
"COMMIT_EDITMSG",
"config",
"description",
"HEAD",
"index",
"packed-refs"
);

my @commits;
my $ua = LWP::UserAgent->new;
$ua->agent($config{'agent'});

my $gd=$config{'gitdir'}."/";

mkdir $gd;

print STDERR "[i] Downloading git files from $config{'url'}\n" if ($config{'verbose'}>0);

foreach my $file (@gitfiles) {
	my $furl = $config{'url'}."/".$file;
	getfile($file,$gd.$file);
}

mkdir $gd."logs";
mkdir $gd."logs/refs";
mkdir $gd."logs/refs/heads";
mkdir $gd."logs/refs/remotes";

mkdir $gd."objects";
mkdir $gd."objects/info";
mkdir $gd."objects/pack";

getfile("objects/info/alternates",$gd."objects/info/alternates");

mkdir $gd."info";
getfile("info/grafts",$gd."info/grafts");

my $res = getfile("logs/HEAD",$gd."logs/HEAD");

my @lines = split /\n/, $res->content;
foreach my $line (@lines) {
	my @fields=split(/\s+/, $line);
	my $ref = $fields[1];
	getobject($gd,$ref);
}

mkdir $gd."refs";
mkdir $gd."refs/heads";
my $res = getfile("refs/heads/".$config{'branch'},$gd."refs/heads/".$config{'branch'});
mkdir $gd."refs/remotes";
mkdir $gd."refs/tags";

my $pcount=1;
while ($pcount>0) {
	print STDERR "[i] Running git fsck to check for missing items\n" if ($config{'verbose'}>0);
	open(PIPE,"git fsck |") or die "cannot find git: $!";
	$pcount=0;
	while (<PIPE>) {
		chomp;
		if (/^missing/) {
			my @getref = split (/\s+/);
			getobject($gd,$getref[2]); # 3rd field is sha1 
			$pcount++;
		}
	}
	close(PIPE);
	print STDERR "[i] Got items with git fsck: $pcount\n" if ($config{'verbose'}>0);
}

if ($config{'checkout'}) {
	system("git checkout -f");
}


sub getobject {
	my ($gd,$ref) = @_;
	my $rdir = substr ($ref,0,2);
	my $rfile = substr ($ref,2);
	mkdir $gd."objects/$rdir";
	getfile("objects/$rdir/$rfile",$gd."objects/$rdir/$rfile");
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
	print "DVCS-Ripper: rip-git.pl. Copyright (C) Kost. Distributed under GPL.\n\n";
	print "Usage: $0 [options] -u [giturl] \n";
	print "\n";
	print " -c	perform 'git checkout -f' on end (default)\n";
	print " -b <s>	Use branch <s> (default: $config{'branch'})\n";
	print " -a <s>	Use agent <s> (default: $config{'agent'})\n";
	print " -s	verify SSL cert\n";
	print " -v	verbose (-vv will be more verbose)\n";
	print "\n";

	print "Example: $0 -v -u http://www.example.com/.git/\n";
	print "Example: $0 # with url and options in $configfile\n";
	
	exit 0;
}

