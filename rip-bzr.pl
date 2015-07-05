#!/usr/bin/perl

use strict;

use IO::Socket::SSL;
use LWP;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use Getopt::Long;
use Cwd;

my $configfile="$ENV{HOME}/.rip-bzr";
my %config;
$config{'bzrdir'} = ".bzr";
$config{'agent'} = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.7; rv:10.0.2) Gecko/20100101 Firefox/10.0.2';
$config{'verbose'}=0;
$config{'checkout'}=1;

$config{'respdetectmax'}=3;
$config{'resp404size'}=256;
$config{'resp404reqsize'}=32;

sub randomstr  {
	my($num) = @_;
	my @chars = ("A".."Z", "a".."z");
	my $string;
	$string .= $chars[rand @chars] for 1..$num;
	return $string;
}

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
	"p|proxy=s" => \$config{'proxy'},
	"c|checkout!" => \$config{'checkout'},
	"s|sslignore!" => \$config{'sslignore'},
	"v|verbose+"  => \$config{'verbose'},
	"h|help" => \&help
);

my @knownfiles=(
	'branch-format',
	'branch/branch.conf',
	'branch/format',
	'branch/last-revision',
	'branch/tags',
	'checkout/conflicts',
	'checkout/dirstate',
	'checkout/format',
	'checkout/merge-hashes',
	'checkout/views',
	'repository/format',
	'repository/pack-names'
);

my $ua = LWP::UserAgent->new;

$ua->agent($config{'agent'});

if ($config{'sslignore'}) {
	$ua->ssl_opts(SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE, verify_hostname => 0);
}
if ($config{'proxy'}) {
	# for socks proxy make sure you have LWP::Protocol::socks
	$ua->proxy(['http', 'https'], $config{'proxy'});
}

my $ddir=$config{'bzrdir'}."/";

mkdir $ddir;
mkdir $ddir."branch";
mkdir $ddir."checkout";
mkdir $ddir."repository";
mkdir $ddir."repository/indices";
mkdir $ddir."repository/packs";

print STDERR "[i] Downloading bzr files from $config{'url'}\n" if ($config{'verbose'}>0);

my @resp404;
my $respdetectmax=$config{'respdetectmax'};
print STDERR "[i] Auto-detecting 404 as 200 with $config{'respdetectmax'} requests\n" if ($config{'verbose'}>0);
$config{'resp404correct'}=0;
for (my $i=0; $i<$respdetectmax;$i++) {
	my $resp=getreq(randomstr($config{'resp404reqsize'}));
	if ($resp->is_success) {
		push @resp404, $resp;
	} else {
		$config{'resp404correct'}=1;
		last; # exit loop
	}
}

if ($config{'resp404correct'}) {
	print STDERR "[i] Getting correct 404 responses\n";
} else {
	print STDERR "[i] Getting 200 as 404 responses. Adapting...\n";
	my $oldchopresp = substr($resp404[0]->content,0,$config{'resp404size'});
	foreach my $entry (@resp404) {
		my $chopresp=substr($entry->content,0,$config{'resp404size'});
		if ($oldchopresp eq $chopresp) {
			$oldchopresp=substr($entry->content,0,$config{'resp404size'});
		} else {
			print STDERR "[i] 404 responses are different, you will have to customize script source code\n";
			$config{'resp404content'}=$chopresp;
			last; # exit loop
		}
	}
	$config{'resp404content'}=$oldchopresp;
}

foreach my $file (@knownfiles) {
	getfile($file,$ddir.$file);
}


my $tofetch=0;
my $fetched=0;
my $pcount=1;
my $fcount=0;
while ($pcount>0) {
	print STDERR "[i] Running bzr check to check for missing items\n" if ($config{'verbose'}>0);
	open(PIPE,"bzr check 2>&1 |") or die "cannot find bzr: $!";
	$pcount=0;
	$fcount=0;
	while (<PIPE>) {
		print $_ if ($config{'verbose'}>9);
		chomp;
		if (/ERROR:/) {
			$tofetch++;
			m/'(.*?)'/;
			my $missingfile = $1;
			my $curdir = getcwd."/".$config{'bzrdir'}."/";
			substr $missingfile, index($missingfile, $curdir), length $curdir, '';
			print STDERR "[i] Getting $missingfile\n" if ($config{'verbose'}>0);
			my $res=getfile($missingfile,$ddir.$missingfile);
			if ($res->is_success) {
				$fcount++;
				$fetched++;
			}
			$pcount++;
		}
	}
	close(PIPE);
	print STDERR "[i] Got items with bzr check: $pcount\n" if ($config{'verbose'}>0);
	print STDERR "[i] Items fetched: $fcount\n" if ($config{'verbose'}>0);
	if ($fcount == 0) {
		last;
	}
}

print STDERR "[i] Finished fetching ($fetched/$tofetch)\n";

if ($config{'checkout'}) {
	print STDERR "[i] Checking out/Reverting source by calling bzr revert\n";
	system("bzr revert");
}

# -- END

sub getreq {
	my ($file) = @_;
	my $furl = $config{'url'}."/".$file;
	my $req = HTTP::Request->new(GET => $furl);
	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);
	return $res;
}

sub getfile {
	my ($file,$outfile) = @_;
	my $furl = $config{'url'}."/".$file;
	my $req = HTTP::Request->new(GET => $furl);
	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);
	if ($res->is_success) {
		if (not $config{'resp404correct'}) {
			print STDERR "[d] got 200 for $file, but checking content\n" if ($config{'verbose'}>1);;
			my $chopresp=substr($res->content,0,$config{'resp404size'});
			if ($chopresp eq $config{'resp404content'}) {
				print STDERR "[!] Not found for $file: 404 as 200\n" 
				if ($config{'verbose'}>0);
				return $res;
			}
		} 
		print STDERR "[d] found $file\n" if ($config{'verbose'}>0);;
		open (out,">$outfile") or die ("cannot open file $outfile: $!");
		print out $res->content;
		close (out);
	} else {
		print STDERR "[!] Not found for $file: ".$res->status_line."\n" 
		if ($config{'verbose'}>0);
	}
	return $res;
}

sub help {
	print "DVCS-Ripper: rip-bzr.pl. Copyright (C) Kost. Distributed under GPL.\n\n";
	print "Usage: $0 [options] -u [bzrurl] \n";
	print "\n";
	print " -c	perform 'bzr revert' on end (default)\n";
	print " -b <s>	Use branch <s> (default: $config{'branch'})\n";
	print " -a <s>	Use agent <s> (default: $config{'agent'})\n";
	print " -s	do not verify SSL cert\n";
	print " -p <h>	use proxy <h> for connections\n";
	print " -v	verbose (-vv will be more verbose)\n";
	print "\n";
	print "Example: $0 -v -u http://www.example.com/.bzr/\n";
	print "Example: $0 # with url and options in $configfile\n";
	print "Example: $0 -v -u -p socks://localhost:1080 http://www.example.com/.bzr/\n";
	print "For socks like proxy, make sure you have LWP::Protocol::socks\n";
	
	exit 0;
}

