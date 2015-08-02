dvcs-ripper
===========

Rip web accessible (distributed) version control systems: SVN, GIT, Mercurial/hg, bzr, ...

It can rip repositories even when directory browsing is turned off. 

Make sure to position yourself in empty directory where you want repositories to be downloaded/cloned.

## Requirements

- Perl
- Perl modules: 
  - required: LWP, IO::Socket::SSL 
  - for newer SVN: DBD::SQlite and DBI
  - for faster GIT: Parallel::ForkManager and Redis
- (D)VCS client of what you want to rip (cvs, svn, git, hg, bzr, ...)

### Requirements on Debian/Ubuntu

You can easily install perl requirements:

`sudo apt-get install perl libio-socket-ssl-perl libdbd-sqlite3-perl libclass-dbi-perl`

Optional requirements (faster git rip):
`sudo apt-get install libparallel-forkmanager-perl libredis-perl`

And if you need all clients supported:

`sudo apt-get install cvs subversion git bzr mercurial`

## Docker

In case you just want docker version, it is here:

https://github.com/kost/docker-webscan/tree/master/alpine-dvcs-ripper

Just say something like:

`docker run --rm -it -v /path/to/host/work:/work:rw k0st/alpine-dvcs-ripper rip-git.pl -v -u http://www.example.org/.git`


GIT
===========
Example run (for git):

`rip-git.pl -v -u http://www.example.com/.git/`

It will automatically do `git checkout -f`

or if you would like to ignore SSL certification verification (with -s):

`rip-git.pl -s -v -u http://www.example.com/.git/`

Mercurial/HG
===========
Example run (for hg):

`rip-hg.pl -v -u http://www.example.com/.hg/`

It will automatically do `hg revert <file>`

or if you would like to ignore SSL certification verification (with -s):

`rip-hg.pl -s -v -u http://www.example.com/.hg/`

Bazaar/bzr
===========
Example run (for bzr):

`rip-bzr.pl -v -u http://www.example.com/.bzr/`

It will automatically do `bzr revert`

or if you would like to ignore SSL certification verification (with -s):

`rip-bzr.pl -s -v -u http://www.example.com/.bzr/`


SVN
===========
It supports OLDER and NEWER version of svn client formats. Older is with .svn files in every directory, while
newer version have single .svn directory and wc.db in .svn directory. It will automatically detect which 
format is used on the target.

Example run (for SVN):

`rip-svn.pl -v -u http://www.example.com/.svn/`

It will automatically do `svn revert -R .`

CVS
===========
Example run (for CVS):

`rip-cvs.pl -v -u http://www.example.com/CVS/`

This will not rip CVS, but it will display useful info.

### ToDo
- [ ] Recognize 404 pages which return 200 in SVN/CVS
- [ ] Support for brute forcing pack names 

### Done
- [x] Support for objects/info/packs from https://www.kernel.org/pub/software/scm/git/docs/gitrepository-layout.html
- [x] Recognize 404 pages which return 200 
- [x] Introduce ignore SSL/TLS verification in SVN/CVS
- [x] Bzr support

