nagboard
========

Introduction
------------

This is a little hack I wrote a while ago, inspired by a custom Flash app used
at a previous place of work.  It consists of a bit of HTML that serves as a wrapper
for a perl CGI script which gives you a scoreboard-like display.

It's designed to be used on a big screen that is visible to all your ops staff.
I display it in Firefox with the 'Full Fullscreen' plugin to get rid of all the
browser decoration, so all you're left with is the scoreboard.

Prerequisites
-------------

You need a working Nagios installation that uses a database as a back end.  For
most installations this means using 'ndo2db'; on Debian-like systems, the package
'ndoutils' will provide what you want.

Installation
------------

Take 'nagboard.html' and 'nagboard.pl' and bung them in a directory on your Nagios
server that Apache can see.  I use this directory and set of Apache directives:

	<Directory "/var/www/nagboard/">
		AllowOverride None
		Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
		AddHandler cgi-script .pl
	</Directory>

You might need to tweak a couple of things in the perl script.  Nagboard will
display some mrtg graphs when there are no alarms, so you'll have to substitute
the URLs for those graphs.  If you don't want it to do that, just leave the URLs
commented out.  The other thing is the database access details: 'localhost' will
be fine if you're running this on the same server as your Nagios installation
(recommended).  You'll just need to provide the username and password for your
ndo2db database user.

Other stuff
-----------

I'm a sysadmin, not a programmer, and the code might be very unpleasant.  There
are lots of features that would be nice to have.  Feel free to request them or to
send me patches, but please be nice.  Bitching about my code is pointless.

