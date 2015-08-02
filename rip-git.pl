#!/usr/bin/perl

use strict;

use IPC::SysV qw(IPC_PRIVATE S_IRWXU IPC_CREAT SEM_UNDO ftok);
use IPC::Semaphore;
use IPC::SharedMem;

use IO::Socket::SSL;
use LWP;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Response;
use Getopt::Long;

my $configfile="$ENV{HOME}/.rip-git";
my %config;
$config{'branch'} = "master";
$config{'gitdir'} = ".git";
$config{'agent'} = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.7; rv:10.0.2) Gecko/20100101 Firefox/10.0.2';
$config{'verbose'}=0;
$config{'checkout'}=1;

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
	"u|url=s" => \$config{'url'},
	"p|proxy=s" => \$config{'proxy'},
	"c|checkout!" => \$config{'checkout'},
	"s|sslignore!" => \$config{'sslignore'},
	"t|tasks=s" => \$config{'tasks'},
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
		print STDERR "[!] No items successfully fetched any more. Exiting\n"; 
		last;
	}
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
	print " -a <s>	Use agent <s> (default: $config{'agent'})\n";
	print " -s	do not verify SSL cert\n";
	print " -t <i>	use <i> parallel tasks\n";
	print " -p <h>	use proxy <h> for connections\n";
	print " -v	verbose (-vv will be more verbose)\n";
	print "\n";
	print "Example: $0 -v -u http://www.example.com/.git/\n";
	print "Example: $0 # with url and options in $configfile\n";
	print "Example: $0 -v -u -p socks://localhost:1080 http://www.example.com/.git/\n";
	print "For socks like proxy, make sure you have LWP::Protocol::socks\n";
	
	exit 0;
}

