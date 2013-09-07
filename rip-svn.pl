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
$config{'outdir'}='./';
$config{'upgrade'}=1;

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
"all-wcprops",
"entries",
"format",
"wc.db"
);

if ($config{'verbose'}>3) {
	foreach my $key ( keys %config )
	{
	  print "$key => $config{$key}\n";
	}
}

my @commits;
my $ua = LWP::UserAgent->new;
$ua->agent($config{'agent'});

# normalize URL
if ($config{'url'} =~ /\/\.svn/) {
	$config{'scmurl'} = $config{'url'};
	$config{'regurl'} = $config{'url'};
	$config{'regurl'} =~ s/\/\.svn//;
} else {
	$config{'scmurl'} = $config{'url'}."/.svn";
	$config{'regurl'} = $config{'url'};
}

createsvndirs($config{'outdir'});
downloadsvnfiles('',$config{'outdir'});

if (-e "$config{'scmdir'}/wc.db") {
	print STDERR "[i] Found new SVN client storage format!\n";
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
			getobject("$config{'outdir'}/$config{'scmdir'}",$nfile); 
		} else {
			warn("Unknown checksum: $record->{'checksum'}");
		}
	}
	$dbh->disconnect;
	checkout();

} else {
	if (-e "$config{'scmdir'}/entries") {
		print STDERR "[i] Found old SVN client storage format!\n";
		svnentries('',$config{'outdir'});
		if ($config{'checkout'} and $config{'upgrade'}) {
			print STDERR "[i] Running upgrade, if you get errors, ignore if using older client\n";
			system("svn upgrade");
		}
		checkout();
		print STDERR "[i] Due to limitations, to get full tree - run this utility few times!\n";
	} else {
		print STDERR "[i] Could not identify SVN format. Are you sure it's SVN there?\n";
		print STDERR "[i] Anyway, take a look at ".$config{'scmurl'}."/"."entries\n";
	}
}	

sub checkout {
	if ($config{'checkout'}) {
		print STDERR "[i] Trying to revert the tree, if you get error, upgrade your SVN client!\n";
		system("svn revert -R .");
	}
}

sub createsvndirs {
	my ($dir) = @_;
	mkdir $dir."/.svn";
	mkdir $dir."/.svn/text-base";
	mkdir $dir."/.svn/pristine";
	mkdir $dir."/.svn/tmp";
}

sub downloadsvnfiles {
	my ($url,$dir) = @_;
	foreach my $file (@scmfiles) {
		my $furl = "$url/$config{'scmdir'}/$file";
		getfile($furl,"$dir/$config{'scmdir'}/$file");
	}
}

sub svnentries {
	my ($url, $dir) = @_;

	createsvndirs("$dir");
	my $svnentries = "$dir/$config{'scmdir'}/entries";
	# getfile("/$svnentries","$dir/$svnentries");
	# my $file="$dir/$svnentries";	

	downloadsvnfiles($url,$dir);
	
	open(SVN,"<$svnentries") or warn ("cannot open entries file '$svnentries': $!\n");
	my $prevline;
	while (<SVN>) {
		chomp;
		if ($_ eq "dir") {
			if (not $prevline eq '') {
				my $newdir=$prevline;
				if (not -e $newdir) {	
					mkdir $newdir;
					svnentries("$url/$newdir","$dir/$newdir");
				}
			}
		}

		if ($_ eq "file") {
			my $newfile=$prevline;
			getfile("$url/.svn/text-base/$newfile.svn-base","$dir/.svn/text-base/$newfile.svn-base");
		}
		$prevline=$_;
	}	
	close(SVN);
}


sub getobject {
	my ($gd,$ref) = @_;
	my $rdir = substr ($ref,0,2); # first two chars of sha1 is dirname
	my $rfile = $ref.".svn-base"; # whole sha1 is filename
	mkdir $gd."/pristine/$rdir";
	getfile($config{'scmdir'}."/pristine/$rdir/$rfile",$gd."/pristine/$rdir/$rfile");
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

