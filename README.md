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
  - for faster GIT: Parallel::ForkManager, Redis and Algorithm::Combinatorics
- (D)VCS client of what you want to rip (cvs, svn, git, hg, bzr, ...)

### Requirements on Debian/Ubuntu

You can easily install perl requirements:

`sudo apt-get install perl libio-socket-ssl-perl libdbd-sqlite3-perl libclass-dbi-perl libio-all-lwp-perl`

Optional requirements (faster git rip):
`sudo apt-get install libparallel-forkmanager-perl libredis-perl libalgorithm-combinatorics-perl`

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

## Advance usage examples

Some examples how it can be used

### Output handling

Download git tree to specific output dir:

`rip-git.pl -o /my/previously/made/dir -v -u http://www.example.com/.git/`

Download git tree to specific output dir (creating dir `http__www.example.com_.git_` for url):

`rip-git.pl -m -o /dir -v -u http://www.example.com/.git/`

### Redis usage with docker

Create Redis docker container:

`docker run --rm --name myredis -it -v /my/host/dir/data:/data:rw k0st/alpine-redis`

In another terminal, just link redis container and say something like this:

`docker run --rm --link=myredis:redis -it -v /path/to/host/work:/work:rw k0st/alpine-dvcs-ripper rip-git.pl -e docker -v -u http://www.example.org/.git -m -o /work`

### Using redis for resuming work of ripping

Create Redis docker container:

`docker run --name redisdvcs -it -v /my/host/dir/data:/data:rw k0st/alpine-redis`

In another terminal, just link redis container and say something like this:

`docker run --link=redisdvcs:redis -it -v /path/to/host/work:/work:rw k0st/alpine-dvcs-ripper rip-git.pl -n -e docker -v -u http://www.example.org/.git -m -o /work`

### Abusing redis for massive parallel tasks

Create global NFS and mount /work on each client. Create global Redis docker container:

`docker run --name redisdvcs -it -v /my/host/dir/data:/data:rw k0st/alpine-redis`

In another terminal, just link redis container and say something like this on 1st client

`docker run -it -v /path/to/host/work:/work:rw k0st/alpine-dvcs-ripper rip-git.pl -n -e global.docker.ip -v -u http://www.example.org/.git -t 10 -c -m -o /work`

In another terminal, just link redis container and say something like this on 2nd client:

`docker run -it -v /path/to/host/work:/work:rw k0st/alpine-dvcs-ripper rip-git.pl -n -e global.docker.ip -v -u http://www.example.org/.git -t 10 -c -m -o /work`

and so on...

You need to perform `git checkout -f` yourself on the end - of course!

## Future

Feel free to implement something and send pull request. Feel free to suggest any feature. Lot of features
actually were implemented by request

### ToDo
- [ ] Recognize 404 pages which return 200 in SVN/CVS
- [ ] Try to repeat each trick after previous trick was successful
- [ ] Progress bars

### Done
- [x] Support for brute forcing pack names 
- [x] Inteligent guessing of packed refs
- [x] Support for objects/info/packs from https://www.kernel.org/pub/software/scm/git/docs/gitrepository-layout.html
- [x] Recognize 404 pages which return 200 
- [x] Introduce ignore SSL/TLS verification in SVN/CVS
- [x] Bzr support

