dvcs-ripper
===========

Rip web accessible (distributed) version control systems: SVN, GIT, Mercurial/hg, ...

It can rip repositories even when directory browsing is turned off. 

Make sure to position yourself in empty directory where you want repositories to be downloaded/cloned.


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


### Todo
- [x] Support for objects/info/packs from https://www.kernel.org/pub/software/scm/git/docs/gitrepository-layout.html
- [ ] Support for brute forcing pack names 
- [x] Recognize 404 pages which return 200 
- [x] Introduce ignore SSL/TLS verification in SVN/CVS



