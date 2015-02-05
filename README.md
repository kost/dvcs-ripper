dvcs-ripper
===========

Rip web accessible (distributed) version control systems: SVN, GIT, ...

It can rip repositories even when directory browsing is turned off. 

Make sure to position yourself in empty directory where you want repositories to be downloaded/cloned.


GIT
===========
Example run (for git):

`rip-git.pl -v -u http://www.example.com/.git/`

It will automatically do `git checkout -f`

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
