#! /usr/bin/perl
require './Clui.pm'; import Term::Clui;

&check_kit;
&check_infrastructure('CGI.pm','CGI::FormBuilder.pm','Crypt::Tea.pm');

print STDERR <<EOT;
The behaviour of this script varies according to which directories
you can write to; therefore you should run it as the same user (eg
root) that will execute the 'make install' step.

It will end up installing the module  Htauth.pm, and also possibly
its manual page and a demo CGI script.

Use the arrow keys (or h,j,k,l) and <Return> to make your choices.

EOT

my $version = '1.10';
# my $bindir  = &bindir;
my ($cgidir, $url, $webuser) = &cgidir;
my $libdir  = &libdir . '/CGI';
my $mandir  = &mandir;
my $comment = &comment;
my $perlbin = &which('perl');
if (! $perlbin) { die "Sorry, no perl in PATH\n"; }

# ----------  first build the 'Makefile' ...

if (! open (F, '> Makefile')) { die "Sorry, can't open Makefile: $!\n"; }
if ($libdir)  { print F "LIBDIR = $libdir\n"; }
if ($cgidir)  { print F "CGIDIR = $cgidir\n"; }
if ($mandir)  { print F "MANDIR = $mandir\n"; }

print F <<'EOT';

local : Htauth.pm htauth_demo.cgi

EOT
if ($cgidir || $mandir) { print F <<'EOT';
install : local ${LIBDIR}/Htauth.pm \
EOT
	if ($cgidir && $mandir) { print F <<'EOT';
${CGIDIR}/htauth_demo.cgi \
${MANDIR}/CGI_Htauth.3
EOT
	} elsif ($cgidir) { print F <<'EOT';
${CGIDIR}/htauth_demo.cgi
EOT
	} else { print F <<'EOT';
${MANDIR}/CGI_Htauth.3
EOT
	}
} else { print F <<'EOT';
install : local ${LIBDIR}/Htauth.pm
EOT
}

print F <<'EOT';

Htauth.pm : localise Htauth.raw
	./localise Htauth.raw > $@

htauth_demo.cgi : localise htauth_demo.raw
	./localise htauth_demo.raw > $@

${LIBDIR}/Htauth.pm : Htauth.pm
	perl -c Htauth.pm
	test -d ${LIBDIR} || mkdir ${LIBDIR}
	chmod 755 ${LIBDIR}
	cp Htauth.pm $@
	chmod 644 $@

EOT

if ($cgidir) { print F <<'EOT'; }
${CGIDIR}/htauth_demo.cgi : htauth_demo.cgi
	perl -c htauth_demo.cgi
	cp htauth_demo.cgi $@
	chmod 755 $@

EOT

if ($mandir) { print F <<'EOT'; }
${MANDIR}/CGI_Htauth.3 : Htauth.pm
	pod2man Htauth.pm > $@
	chmod 644 $@

EOT

print F <<EOT;
test :
	perl test_script
EOT

close F;

# ---------  now build the 'localise' script ...

if (! open (F, '> localise')) { die "Sorry, can't open localise: $!\n"; }
print F "#! $perlbin\nwhile (<>) {\n";
if ($comment) { $comment =~ s#/#\\/#g; print F "\ts/#COMMENT#/$comment/;\n"; }
$perlbin =~ s#/#\\/#g; print F "\ts/#PERLBIN#/$perlbin/;\n";
$libdir  =~ s#/#\\/#g; print F "\ts/#LIBDIR#/$libdir/;\n";
$cgidir  =~ s#/#\\/#g; print F "\ts/#CGIDIR#/$cgidir/;\n";
if ($version) { print F "\ts/#VERSION#/$version/;\n"; }
print F "\tprint;\n}\n";
close F;
chmod 0744, 'localise';

print "\nNow try 'make' then 'make test' and then 'make install' . . .\n";
exit 0;

# --------------------- infrastructure ---------------------

sub bindir {
	my (@tried, @writeable);
	foreach $dir (split /:/,$ENV{PATH}) {
		next if ($dir =~ /sbin$|\/root/);
		next if ($dir eq '.');
		push @tried, $dir;
		if (-w $dir) { push @writeable, $dir; }
	}
	if (! @writeable) { print STDERR <<EOT, "   ", join ("\n   ", @tried), "\n" ;
Sorry, can't write to any directories in your PATH; tried
EOT
		exit 1;
	} else {
		$bindir = &choose("Where should the executables be installed ?",
			@writeable, 'Somewhere else');
		if ($bindir eq 'Somewhere else') {
			$bindir = &ask('in which directory, then ?');
			if (! $bindir) { die "not installing, nowhere to install\n"; }
			if (! -d $bindir) { die "Sorry, $bindir is not a directory.\n"; }
			if (! -w $bindir) { die "Sorry, $bindir is not writeable.\n"; }
		}
		if (! $bindir) { die "Sorry, nowhere to install the executables\n"; }
	}
	$bindir =~ s/\/$//;
	return $bindir;
}

sub cgidir {
	my (@tried, @writeable, %cgidirs, $cgidir, %webusers);
	my @configfiles = (
		'/etc/httpd/httpd.conf',
		'/etc/httpd.conf',
		'/usr/local/etc/httpd/httpd.conf',
		'/usr/local/etc/httpd/srm.conf',
	);
	my (@existing, @readable);
	foreach $file (@configfiles) {
		my ($cgid, $url, $webuser);
		if (-f $file) { push @existing, $file; } else { next; }
		next unless open (F, $file);
		push @readable, $file;
		while (<F>) {
			if (/^\s*ScriptAlias\s+(\S+)\s+(\S+)$/) {
				$url = $1; $cgid = $2;
				$cgid =~ s/^"(.*)"$/$1/;
				$cgidirs{$cgid} = $url;
				if ($webuser) { $webusers{$cgid} = $webuser; }
			} elsif (/^\s*User\s+(\S+)$/) {
				$webuser = $1;
				if ($cgid) { $webusers{$cgid} = $webuser; }
			}
		}
		close F;
	}
	foreach $dir (keys %cgidirs) {
		push @tried, $dir;
		if (-w $dir) { push @writeable, $dir; }
	}

	if (! @existing) {
		print STDERR <<EOT, "   ", join ("\n   ", @configfiles), "\n" ;
Hmm, can't find any httpd config files; tried
EOT
	} elsif (! @readable) {
		print STDERR <<EOT, "   ", join ("\n   ", @existing), "\n" ;
Hmm, can't read any httpd config files; tried
EOT
	} elsif (! %cgidirs) {
		print STDERR <<EOT, "   ", join ("\n   ", @readable), "\n" ;
Hmm, can't find any cgi-bin directories in the config files; tried
EOT
	} elsif (! @writeable) {
		print STDERR <<EOT, "   ", join ("\n   ", @tried), "\n" ;
Hmm, can't write to any of the cgi-bin directories; tried
EOT
	}

	if (@writeable) {
		$cgidir = &choose( "Where should the test/demo CGI be installed ?",
			@writeable, 'Somewhere else', 'Do not install it');
	} else {
		$cgidir = 'Somewhere else';
	}

	if (! $cgidir) { return ''; }
	if ($cgidir =~ /^Do not install/) { return ''; }
	if ($cgidir eq 'Somewhere else') {
		$cgidir = &ask('in which directory, then ?');
		if (! $cgidir)    { return ''; }
		if (! -d $cgidir) { die "Sorry, $cgidir is not a directory.\n"; }
		if (! -w $cgidir) { die "Sorry, $cgidir is not writeable.\n"; }
	}
	my $url = $cgidirs{$cgidir};
	my $webuser = $webusers{$cgidir};
	$url =~ s/\/$//;
	$cgidir =~ s/\/$//;
	return ($cgidir, $url, $webuser);
}

sub libdir {
	my (@libdirs, @tried, @writeable, $libdir);
	@libdirs = grep (!/^\.$/, @INC);
	if ($cgidir) { unshift @libdirs, $cgidir; }
	foreach $dir (@libdirs) {
		next if ($dir eq '.');
		push @tried, $dir;
		if (-w $dir) { push @writeable, $dir; }
	}
	if (! @writeable) {
		print STDERR <<'EOT';

Where should the Perl module be installed ? You don't have write permission
to any of the directories in your @INC path; if you wish to install in some
EOT
		$libdir = &ask('other directory, enter it :');
		if (! $libdir) { die "not installing, nowhere to install module\n"; }
		if (! -d $libdir) { die "Sorry, $libdir is not a directory.\n"; }
		if (! -w $libdir) { die "Sorry, $libdir is not writeable.\n"; }
	} else {
		$libdir = &choose("Where should the Perl module be installed ?",
			@writeable, 'Somewhere else');
		if ($libdir eq 'Somewhere else') {
			$libdir = &ask('in which directory, then ?');
			if (! $libdir) { die "not installing, nowhere to install\n"; }
			if (! -d $libdir) { die "Sorry, $libdir is not a directory.\n"; }
			if (! -w $libdir) { die "Sorry, $libdir is not writeable.\n"; }
		}
		if (! $libdir) { die "Sorry, nowhere to install the Perl libraries\n"; }
	}
	$libdir =~ s/\/$//;
	return $libdir;
}

sub mandir {
	my (@tried, @writeable, $mandir);
	foreach $dir (split(/:/, $ENV{MANPATH})) {
		$dir =~ s/$/\/man3/;
		push @tried, $dir;
		if (-w $dir) { push @writeable, $dir; }
	}
	if (! @writeable) { print STDERR <<EOT, "   ", join ("\n   ", @tried), "\n" ;

Sorry, can't write to any directories in your MANPATH; tried
EOT
	}
	$mandir = &choose(
		"Where should the manual pages be installed ?",
		@writeable, 'Somewhere else', 'Do Not Install Manual Pages');
	if ($mandir eq 'Somewhere else') {
		$mandir = &ask('in which directory, then ?');
		if (! $mandir) { die "not installing, nowhere to install\n"; }
		if (! -d $mandir) { die "Sorry, $mandir is not a directory.\n"; }
		if (! -w $mandir) { die "Sorry, $mandir is not writeable.\n"; }
	} elsif ($mandir eq 'Do Not Install Manual Pages') {
		return '';
	} elsif (! $mandir) {
		die "Sorry, nowhere to install the manual pages\n";
	}
	$mandir =~ s/\/$//;
	return $mandir;
}
sub comment {
	my $user = (getpwuid($>))[$[];
	my $build_dir = `pwd`; $build_dir =~ s/\s+$//;
	my $datestamp = &datestamp;
	return "made $datestamp by $user in $build_dir";
}

sub which { my $file = $_[$[];   # looks for executables, Perl libraries
	return '' unless $file;
	my $absfile;
	if ($file =~ /\.p[lm]$/) {   # perl library or module ?
		$file =~ s/::/\//g;
		foreach $dir (@INC) {
			$absfile = "$dir/$file";   return $absfile if -r $absfile;
		}
	} else {   # executable ?
		foreach $dir (split (":", $ENV{PATH})) {
			$absfile = "$dir/$file";   return $absfile if -x $absfile;
		}
	}
}
sub datestamp { # returns current date in "19940314" format
	local ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
	sprintf ("%4.4d%2.2d%2.2d", $year+1900, $mon+1, $mday);
}
sub check_infrastructure {
	my @missing; foreach (@_) { if (! &which($_)) { push @missing, $_; } }
	if (@missing == 1) {
		print STDERR <<EOT;
WARNING: The module $missing[$[] is needed but is not installed.
It can be obtained through www.cpan.org/SITES.html

EOT
	} elsif (@missing) {
		print STDERR "WARNING: The necessary modules\n   ",
			join ("\n   ",@missing),
			"\nare not installed.  Get them through www.cpan.org/SITES.html\n\n";
	}
}

sub check_kit {
	print STDERR "Checking your kit ... ";

	my %file_sizes = (
		'MANIFEST', 63,
		'Makefile.PL', 9844,
		'Htauth.raw', 39806,
		'htauth_demo.raw', 2248,
	);

	my $problem_found = 0;
	foreach $file (keys %file_sizes) {
		if (! -f $file) {
			if (! $problem_found) { $problem_found = 1; print STDERR "\n"; }
			print STDERR "   missing: $file\n"
		} elsif (-s $file != $file_sizes{$file}) {
			if (! $problem_found) { $problem_found = 1; print STDERR "\n"; }
			my $is = -s $file;
			my $should = $file_sizes{$file};
			print STDERR "   wrong size: $file is $is, should be $should bytes\n"
		}
	}
	if ($problem_found) { exit 1;
	} else { print STDERR "Looks good.\n\n"; return 1;
	}
}
1;
