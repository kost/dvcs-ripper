#!/usr/bin/perl

use strict;

use Cwd;
use IPC::SysV qw(IPC_PRIVATE S_IRWXU IPC_CREAT SEM_UNDO ftok);
use IPC::Semaphore;
use IPC::SharedMem;

use IO::Socket::SSL;
use LWP;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use Getopt::Long;

use Digest::SHA qw(sha1 sha1_hex);

my $configfile="$ENV{HOME}/.rip-git";
my %config;
$config{'branch'} = "master";
$config{'gitdir'} = ".git";
$config{'agent'} = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.7; rv:10.0.2) Gecko/20100101 Firefox/10.0.2';
$config{'verbose'}=0;
$config{'checkout'}=1;

$config{'redirects'}=0;

$config{'respdetectmax'}=3;
$config{'resp404size'}=256;
$config{'resp404reqsize'}=32;

$config{'gitpackbasename'}='pack';

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
	"c|checkout!" => \$config{'checkout'},
	"e|redis=s" => \$config{'redis'},
	"g|guess" => \$config{'intguess'},
	"k|session=s" => \$config{'session'},
	"n|newer" => \$config{'newer'},
	"m|mkdir" => \$config{'mkdir'},
	"o|output=s" => \$config{'output'},
	"p|proxy=s" => \$config{'proxy'},
	"r|redirects=i" => \$config{'redirects'},
	"s|sslignore!" => \$config{'sslignore'},
	"t|tasks=i" => \$config{'tasks'},
	"u|url=s" => \$config{'url'},
	"x|brute" => \$config{'brute'},
	"v|verbose+"  => \$config{'verbose'},
	"ba|basicauth=s"  => \$config{'basicauth'},
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

my $cwd=cwd();
my $urldir=$config{'url'};
$urldir=~s#[;:&~/]#_#ig;

if ($config{'output'}) {
	$cwd = cwd();
	if ($config{'mkdir'}) {
		mkdir $config{'output'}."/".$urldir;
		chdir $config{'output'}."/".$urldir;
	} else {
		chdir $config{'output'};
	}
}

my @commits;
my $ua = LWP::UserAgent->new;

$ua->agent($config{'agent'});
$ua->max_redirect($config{'redirects'});
if($config{'basicauth'}) {
	my $key = sprintf '%s %s', "Basic", $config{'basicauth'};
	$ua->default_header('Authorization' => $key);
}


if ($config{'sslignore'}) {
	$ua->ssl_opts(SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE, verify_hostname => 0);
}
if ($config{'proxy'}) {
	# for socks proxy make sure you have LWP::Protocol::socks
	$ua->proxy(['http', 'https'], $config{'proxy'});
}

my $gd=$config{'gitdir'}."/";

mkdir $gd;

print STDERR "[i] Downloading git files from $config{'url'}\n" if ($config{'verbose'}>0);

if ($config{'verbose'}>2) {
	print STDERR "[i] Using agent: $config{'agent'}\n";
	print STDERR "[i] Using redirects: $config{'redirects'}\n";
	print STDERR "[i] Using proxy: $config{'proxy'}\n";
}

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
	print STDERR "[i] Getting correct 404 responses\n" if ($config{'verbose'}>0);
} else {
	print STDERR "[i] Getting 200 as 404 responses. Adapting...\n" if ($config{'verbose'}>0);
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

unless ($config{'session'}) {
	$config{'session'}=randomstr(8);
}

print STDERR "[i] Using session name: $config{'session'}\n";

my $haveredis = eval
{
	require Redis;
	Redis->import();
	1;
};

my $havealg = eval {
	require Algorithm::Combinatorics;
	Algorithm::Combinatorics->import(qw(variations_with_repetition permutations));
	1;
};

if ($config{'redis'}) {
	if ($haveredis) {
		if ($ENV{'REDIS_PORT_6379_TCP_ADDR'}) {
			print STDERR "[i] Detected redis docker environment variable, overriding: $config{'redis'}\n";
			$config{'redis'}=$ENV{'REDIS_PORT_6379_TCP_ADDR'};
		}
		print STDERR "[i] Using redis: $config{'redis'}\n";
		$config{'redisobj'} = Redis->new(server => $config{'redis'});
		$config{'redis-good'} = $config{'session'}."-good";
		$config{'redis-bad'} = $config{'session'}."-bad";
	} else {
		print STDERR "[i] Please install Perl Redis module\n";
	}
}


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

# process packs file: objects/info/packs
my $infopacks='objects/info/packs';
my $res=getrealreq($infopacks);
if ($res->is_success) {
	print STDERR "[!] found info file for packs, trying to process them: $infopacks\n" if ($config{'verbose'}>0);
	writefile($gd.$infopacks,$res->content);
	my @items=split("\n",$res->content);
	foreach my $item (@items) {
		print STDERR "[d] processing packs entry: $item\n" if ($config{'verbose'}>1);
		my ($imark,$ifile) = split(" ",$item);
		my $packfn="objects/pack/$ifile";
		getfile($packfn,$gd.$packfn);
		$packfn=~s/\.pack$/.idx/g;
		getfile($packfn,$gd.$packfn);
	}
}

# Parallel Tasks magic
my $haveppf = eval
{
  require Parallel::ForkManager;
  Parallel::ForkManager->import();
  1;
};
my $pm;
my $sem;
my $shm;
my $shmsize=16;
if ($config{'tasks'}>0) {
	if ($haveppf) {
		$pm = Parallel::ForkManager->new($config{'tasks'});
		$sem = new IPC::Semaphore( ftok( $0, 0 ), 1, S_IRWXU | IPC_CREAT );
		if ($sem) {
			$sem->setval(0,0);
			$shm = IPC::SharedMem->new(IPC_PRIVATE, 16, S_IRWXU);
		} else {
			die("Error creating IPC Semaphore: $!\n");
		}
		print STDERR "[i] Using $config{'tasks'} parallel tasks\n" if ($config{'verbose'}>0);

	} else {
		print STDERR "[!] Please install Parallel::Prefork CPAN module for parallel requests\n";
		$config{'tasks'}=0;
	}
}

my $pcount=1;
my $fcount=0;
while ($pcount>0) {
	print STDERR "[i] Running git fsck to check for missing items\n" if ($config{'verbose'}>0);
	open(PIPE,"git fsck |") or die "cannot find git: $!";
	$pcount=0;
	$fcount=0;
	if ($config{'tasks'}>0) {
		$sem->setval(0,0);
		$shm->write($fcount,0,$shmsize);
	}
	while (<PIPE>) {
		chomp;
		if (/^missing/) {
			my @getref = split (/\s+/);
			$pcount++;
			if ($config{'tasks'}>0) {
				$pm->start() and next;
				my $res = getobject($gd,$getref[2]); # 3rd field is sha1
				if ($res->is_success) {
					$sem->op( 0, 1, SEM_UNDO );
					$fcount=$shm->read(0, $shmsize);
					$shm->write($fcount+1,0,$shmsize);
					$sem->op( 0, -1, SEM_UNDO );
				}
				$pm->finish;
			} else {
				my $res = getobject($gd,$getref[2]); # 3rd field is sha1
				if ($res->is_success) {
					$fcount++;
				}
			}
		}
	}
	if ($config{'tasks'}>0) {
		print STDERR "[i] Waiting for children to finish\n" if ($config{'verbose'}>0);
		$pm->wait_all_children();
		$fcount = $shm->read(0, $shmsize);
	}
	close(PIPE);
	print STDERR "[i] Got items with git fsck: $pcount, Items fetched: $fcount\n" if ($config{'verbose'}>0);
	if ($fcount == 0) {
		print STDERR "[!] No more items to fetch. That's it!\n";
		last;
	}
}

if ($config{'intguess'}) {
	intguess();
}

if ($config{'brute'}) {
	bruteguess();
}

if ($config{'redisobj'}) {
	print STDERR "[i] Closing redis connection\n" if ($config{'verbose'}>0);
	$config{'redisobj'}->quit;
}

if ($config{'checkout'}) {
	system("git checkout -f");
}

if ($config{'output'}) {
	chdir $cwd;
}

sub bruteguess  {
	print STDERR "[!] Performing pure brute force guessing of packed refs\n";
	my $pmb;
	my @digestchars=qw(0 1 2 3 4 5 6 7 8 9 0 a b c d e f);
	my $iter = variations_with_repetition(\@digestchars, 40);
	if ($config{'tasks'}>0) {
		if ($haveppf) {
			$pmb = Parallel::ForkManager->new($config{'tasks'});
		}
	}
	while (my $c = $iter->next) {
		my $p="";
		foreach my $i (@{$c}) { $p = $p.$i }
		print STDERR "[i] Brute forcing digest item: $p \n" if ($config{'verbose'}>0);
		if ($config{'tasks'}>0) {
			$pmb->start() and next;
			getpackedref($p);
			$pmb->finish;
		} else {
			getpackedref($p);
		}
	}
	if ($config{'tasks'}>0) {
		print STDERR "[i] Waiting for children to finish\n" if ($config{'verbose'}>0);
		$pmb->wait_all_children();
	}
	print STDERR "[!] Finished brute force guessing of packed refs. Does world still exists? :)\n";
}

# get packed refs from given digest
sub getpackedref {
	my ($digest) = @_;

	my $packfn="objects/pack/".$digest.".pack";
	getfile($packfn,$gd.$packfn);
	my $idxfn="objects/pack/".$digest.".idx";
	getfile($idxfn,$gd.$idxfn);
}

# calculate possible digest from array of digests
sub getintitem {
	my ($p) = @_;

	my $sha = Digest::SHA->new(1); # use SHA-1
	foreach my $item (@{$p}) {
		$sha->add($item."\n");
	}
	my $digestguess=$sha->hexdigest();
	getpackedref($digestguess);
}

# try to intelligently guess packed refs
sub intguess  {
	print STDERR "[!] Performing intelligent guessing of packed refs\n";
	my @missingitems = $config{'redis-bad'};
	my $iter = permutations(\@missingitems);
	my $pmg;
	if ($config{'tasks'}>0) {
		if ($haveppf) {
			$pmg = Parallel::ForkManager->new($config{'tasks'});
		}
	}
	while (my $p = $iter->next) {
		print STDERR "[i] Guessing item from permutations\n" if ($config{'verbose'}>0);
		if ($config{'tasks'}>0) {
			$pmg->start() and next;
			getintitem($p);
			$pmg->finish;
		} else {
			getintitem($p);
		}
	}
	if ($config{'tasks'}>0) {
		print STDERR "[i] Waiting for children to finish\n" if ($config{'verbose'}>0);
		$pmg->wait_all_children();
	}
	print STDERR "[!] Finished intelligent guessing of packed refs\n";
}

sub getobject {
	my ($gd,$ref) = @_;
	my $rdir = substr ($ref,0,2);
	my $rfile = substr ($ref,2);
	my $redisc;
	if ($config{'redisobj'}) {
		$redisc = Redis->new(server => $config{'redis'});
	}
	if ($config{'redisobj'}) {
		if ($redisc->hexists($config{'redis-bad'},$ref)) {
			$redisc->quit;
			return HTTP::Response->new(404);
		}
		if ($redisc->hexists($config{'redis-good'},$ref)) {
			$redisc->quit;
			return HTTP::Response->new(200);
		}
		print STDERR "[!] Not found in redis cache: $ref\n" if ($config{'verbose'}>1);;
	}
	mkdir $gd."objects/$rdir";
	my $r=getfile("objects/$rdir/$rfile",$gd."objects/$rdir/$rfile");
	if ($config{'redisobj'}) {
		if ($r->is_success) {
			$redisc->hset($config{'redis-good'}, $ref, 200);
		} else {
			$redisc->hset($config{'redis-bad'}, $ref, 404);
		}
		$redisc->quit;
	}
	return $r;
}

sub getreq {
	my ($file) = @_;
	my $furl = $config{'url'}."/".$file;
	my $req = HTTP::Request->new(GET => $furl);
	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);
	return $res;
}

sub getrealreq {
	my ($file) = @_;
	my $res = getreq($file);
	if ($res->is_success) {
		if (not $config{'resp404correct'}) {
			print STDERR "[d] got 200 for packs but checking content\n" if ($config{'verbose'}>1);
			my $chopresp=substr($res->content,0,$config{'resp404size'});
			if ($chopresp eq $config{'resp404content'}) {
				print STDERR "[!] Not found for: 404 as 200\n"
				if ($config{'verbose'}>0);
				# return not found
				my $r = HTTP::Response->new(404);
				# $r = HTTP::Response->new( $code, $msg, $header, $content )
				return $r;
			}
		}
	}
	return $res;
}

sub writefile {
	my ($file, $content) = @_;
	open(my $fh, '>', $file) or return undef;
	print $fh $content;
	close $fh;
}

sub getfile {
	my ($file,$outfile) = @_;
	if ($config{'newer'}) {
		if (-e $outfile) {
			print STDERR "[!] Not overwriting file: $outfile\n" if ($config{'verbose'}>0);
			my $r = HTTP::Response->new(200);
			return $r;
		}
	}
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
				my $r = HTTP::Response->new(404);
				return $r;
			}
		}
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
	print " -e <s>	Use redis <s> server as server:port\n";
	print " -g	Try to inteligently guess name of packed refs\n";
	print " -k <s>	Use session name <s> for redis (default: random)\n";
	print " -a <s>	Use agent <s> (default: $config{'agent'})\n";
	print " -n	do not overwrite files\n";
	print " -m	mkdir URL name when outputting (works good with -o)\n";
	print " -o <s>	specify output dir\n";
	print " -r <i>	specify max number of redirects (default: $config{'redirects'})\n";
	print " -s	do not verify SSL cert\n";
	print " -t <i>	use <i> parallel tasks\n";
	print " -p <h>	use proxy <h> for connections\n";
	print " -x	brute force packed refs (extremely slow!!)\n";
	print " -v	verbose (-vv will be more verbose)\n";
	print " -ba	<s>	set basic auth key\n";
	print "\n";
	print "Example: $0 -v -u http://www.example.com/.git/\n";
	print "Example: $0 # with url and options in $configfile\n";
	print "Example: $0 -v -u -p socks://localhost:1080 http://www.example.com/.git/\n";
	print "For socks like proxy, make sure you have LWP::Protocol::socks\n";

	exit 0;
}
