dvcs-ripper
===========

Rip web accessible (distributed) version control systems: SVN, GIT, ...

It can rip repositories even when directory browsing is turned off. 

Make sure to position yourself in empty directory where you want repositories to be downloaded/cloned.


GIT
===========
Example run (for git):
rip-git.pl -v -u http://www.example.com/.git/

it will automatically do "git checkout -f"

SVN
===========
It supports newer version of svn client format which has wc.db in .svn directory. 

Example run (for SVN):
rip-svn.pl -v -u http://www.example.com/.svn/

it will automatically do "svn revert -R ."
