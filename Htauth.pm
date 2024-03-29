# Htauth.pm 
#########################################################################
#        This Perl module is Copyright (c) 2000, Peter J Billam         #
#               c/o P J B Computing, www.pjb.com.au                     #
#                                                                       #
#     This module is free software; you can redistribute it and/or      #
#            modify it under the same terms as Perl itself.             #
#########################################################################
#

package CGI::Htauth;
$VERSION = '1.21'; # NOTE: also change version number in POD

use Exporter; @ISA = qw(Exporter);
@EXPORT=qw(initialise_htauth output authenticate set_password $AUTH_USER);

# $dbdir/password/passwd_by_user.dir (and .pag) The database of passwords
# $dbdir/password/user,time_by_htauth_k.dir     The session keys
# $dbdir/password/htauth_c,time_by_ip,user.dir  The challenge for JS to digest
# and each user has 3 (or 4) files ...
# $dbdir/challenge/$user.dir (and .pag)         The database of responses
# $dbdir/challenge/$user.txt  The A4 page which they print out and carry
# $dbdir/challenge/$user.cur  The keynumber of the current challenge

# to fit with FormBuilder ...
# Put htauth_[jkprtux] into %FormBuilder::OURATTR - do that here or there ?

# CGI stuff ...
# $q->param(-name=>'veggie',-value=>'tomato'); to unset a var ?
# $query->delete('foo');
# $query = new CGI('dinosaur=barney&color=purple');
# $q->param_fetch('address')->[1] = '1313 Mockingbird Lane';
# unshift @{$q->param_fetch(-name=>'address')},'George Munster';

# available to all routines in this package ...
my $CGI;   # ref to a CGI, as passed to &initialise_htauth
my %DAT;   # assocary set by &initialise_htauth from $CGI
my $initialised = 0;   # htauth has been run
my $dbdir = '';        # set from config, needed everywhere
my @to_be_output = (); # collected by &output and printed at the right time
my $nkeys = 450;       # number of challenge-response keys on one sheet
my $header_already=0;  # a header has already been output
my $bgcolor = '';      # application body bgcolor, measured by &output
my $fgcolor = '';      # application body fgcolor, measured by &output

sub new {
	my $arg1 = shift;
	my $class = ref($arg1) || $arg1; # can be used as class or instance method
	my $self  = {};   # ref to an empty hash
	bless $self, $class;
	$self->initialise_htauth(shift);
	return $self;
}

sub initialise_htauth { $CGI = shift;
	# waste time recovering the stuff that CGI.pm stole from us
	if (! ref $CGI) {&fatal("initialise_htauth arg must be a CGI ref\n");}
	%DAT = (); foreach ($CGI->param()) { $DAT{$_} = $CGI->param($_); }
	my $t = &timestamp();   # ???
	$initialised = 1;
}

sub debug {
	open T, '>> /tmp/htauth.debug'; print T @_; close T;
}

sub output (@) {  my $str = join '', @_;  # encrypt if necessary, then print
	if ($str =~ /<\/HEAD>/is) { $header_already = 1; }
	if (! $DAT{htauth_j}) { print $str; return 1; }

	if ($str =~ /action="([^"]*)"/is) { # replace ACTION= with javascript:
		# if $1 is not the current script, should log out ? ...
		$str =~
s/action="[^"]*"/action="javascript:parent.encrypt_and_submit(this.document.forms[0]);"/is;
		# "this" is only the window :-( should increment through the forms
	}
	if ($str =~ /^(.*)(<BODY.*)/is) { # if <BODY, print header
		if ($DAT{htauth_r} || $DAT{htauth_t} || $AUTH_USER) {
			print @to_be_output, $1;
		}
		@to_be_output = (); $str = $2;
		if ($str =~ /BGCOLOR="(#\d+)"/is) { $bgcolor = $1; }
		if ($str =~ /TEXT="(#\d+)"/is)    { $fgcolor = $1; }
	}
	if ($str =~ /^(.*)(<\/BODY>.*)/is) { # if </BODY>,
		if ($AUTH_USER) {   # logged in; join encrypt & write
			push @to_be_output, $1;  my $footer = $2;
			&encrypt_and_write((join '',@to_be_output),
				&get_password($DAT{htauth_u}));
			print $footer; return 1;
		} else {  # probably half-way through JS login
			# @to_be_output should be quoted and put into htauth_frame1
			# by &authenticate 
			print @to_be_output, $str; return 1;
		}
	}
	push @to_be_output, $str; return 1;
}

sub authenticate {  my $config = shift;  my $CGIarg = shift;
	if (! $config) { &fatal("can't authenticate: no configuration."); }
	if (! $initialised) {
		&fatal('&initialise_htauth must be called before &authenticate');
	}
	&initialise_htauth($CGIarg);  # in case the application has fiddled vars
	$AUTH_USER = '';

	my @config_lines;
	if ($config !~ /\n/ && -f $config) {
		if (! open (CONFIG_AUTH, $config)) { &fatal("can't open $config: $!\n");
		} else { @config_lines = <CONFIG_AUTH>; close CONFIG_AUTH;
		}
	} else {
		@config_lines = split /\n/, $config;
	}
	# parse @config_lines and deduce $dbdir, $auth_mode and $timeout
	my ($line, $auth_mode, $timeout);
	while (@config_lines) {
		$line = shift @config_lines;
		$line =~ s/\s*#.*$//;   # remove comment
		next unless $line;      # allow empty lines or comment lines
		if ($line =~ /^\s*dbdir\s+(\S+)/) { $dbdir = $1;
		} elsif ($line =~ /^\s*(allow|deny)\s+(.*)$/) {
			$auth_mode = $1; my $remainder = $2;
			if (&ip_matches($ENV{REMOTE_ADDR}, $2)) { last; }
		} elsif ($line =~ /^\s*(password|challenge)\s+(.*)$/) {
			$auth_mode = $1; my $remainder = $2;
			if ($remainder =~ s/\s+timeout\s*=\s*(\d+)//) { $timeout = $1; }
			if (&ip_matches($ENV{REMOTE_ADDR}, $remainder)) { last; }
		} else { output "Unrecognised configuration line :<BR>$line</BR>\n";
		}
	}

	if ($auth_mode eq 'allow') {
		return 1;

	} elsif ($auth_mode eq 'deny') {
		&fatal("access from $ENV{REMOTE_ADDR} is denied.");

	} elsif ($auth_mode eq 'password') {
		if (!$DAT{htauth_u} || (!$DAT{htauth_p} && !$DAT{htauth_j}
		&& !$DAT{htauth_k} && !$DAT{htauth_r})) {
			&zap('htauth_u','htauth_p','htauth_r','htauth_k');
			output "<H2><CENTER>Login&nbsp;.&nbsp;.&nbsp;.</CENTER></H2>\n";
			if (&javascript_supported()) { # we'll try using Tea ...
				# XXX and must also do this on login expiry, see below ...
				eval "require 'Crypt/Tea.pm';";
				if ($@) { &non_js_pw_login();   &footer; exit 0;
				} else  { &js_pw_login_part1(); &footer; exit 0;
				}
			} else {   # browser doesn't support javascript ...
				&non_js_pw_login(); &footer; exit 0;
			}
			&fatal("we shouldn't end up here (line 165 in Htauth.pm)");
		}

		if ($DAT{htauth_u} && $DAT{htauth_j} &&
			!$DAT{htauth_r} && !$DAT{htauth_k}) {
			# We're half way through JavaScript login
			&js_pw_login_part2();   # sets up frameset and hidden forms...
		}

		if ($DAT{htauth_u} && $DAT{htauth_r}) {
			# JavaScript has responded to our challenge ...  We assume that
			# &tea_in_javascript resides in the FRAMESET and the hidden_forms
			# in the top frame htauth_frame0 ... In &output we must fiddle
			# the ACTION= of forms in htauth_frame1 to invoke the JS

			eval "require 'Crypt/Tea.pm';"; if ($@) {
				fatal ("can't require Tea.pm but htauth_r = $DAT{htauth_r} !");
			}
			import Crypt::Tea;

			# check htauth_r response
			my ($htauth_c,$time) = &get_htauth_c_time();

			if ($DAT{htauth_r} ne
				&asciidigest($htauth_c.&get_password($DAT{htauth_u}))) {
				&zap('htauth_u','htauth_r'); # but FormBuilder doesn't notice :-(
				output <<EOT;
<SCRIPT LANGUAGE="JavaScript"> <!--
parent.remember_htauth_p = '';
// -->
</SCRIPT>
<CENTER><P><B>Sorry, wrong password. Please
<A HREF="javascript:parent.htauth_frame0.document.htauth_form1.submit();">
try again</A> or
<A HREF="$ENV{SCRIPT_NAME}" TARGET="_top">
restart</A>&nbsp;.&nbsp;.&nbsp;.</B></P></CENTER>
EOT
				&footer; exit 0;
			}
			# asciidigests are equal, we have a successful login :-)
			$AUTH_USER = $DAT{htauth_u};   # now &output will encrypt ...

			# Add form-vars so far to keep_in_plaintext[] (see Tea.pm)
			# to allow the application to find its way back to here ...
			output "<SCRIPT LANGUAGE=\"JavaScript\"><!--\n";
			foreach $var (sort keys %DAT) {
				if ($var ne 'htauth_t') {
					output "parent.keep_in_plaintext['$var'] = true;\n";
				}
			}
			output "// -->\n</SCRIPT>\n";

			$DAT{htauth_k} = &remember_htauth_k();   # assign htauth_k ...
			&logit('login', $username, 'cyphertext password');
			my $mins = int ($timeout/60);
			&zap('htauth_p'); my $query_string = &query_string(\%DAT);
			$CGI->param(-name=>'htauth_k',-value=>$DAT{htauth_k});
			output <<EOT;
<SCRIPT LANGUAGE="JavaScript"><!--
parent.htauth_frame0.document.htauth_form0.htauth_k.value = '$DAT{htauth_k}';
parent.htauth_frame0.document.htauth_form1.htauth_k.value = '$DAT{htauth_k}';
parent.htauth_frame0.document.htauth_form2.htauth_k.value = '$DAT{htauth_k}';
// -->
</SCRIPT>
<CENTER><P>Welcome $DAT{htauth_u}. This session lasts for $mins&nbsp;minutes.
You may <A HREF="javascript:parent.htauth_change();">change your password</A>
or <A HREF="javascript:parent.htauth_logout();">log out</A>
if you wish.</P></CENTER>
EOT
			return 1;
		}

		if ($DAT{htauth_u} && $DAT{htauth_j} && $DAT{htauth_k}) {

			# ----------- JavaScript is running ; timeout ? -----------
			my $time_from_db = &check_htauth_k();
			if ($time_from_db < (time - $timeout)) {
				&zap('htauth_x','htauth_k');
				output <<EOT;
<P><CENTER><B>Your last login has expired.</CENTER></B></P>
<P><CENTER><A HREF="$ENV{SCRIPT_NAME}">
Restart $ENV{SCRIPT_NAME}</A>&nbsp;.&nbsp;.&nbsp;.</CENTER></P>
EOT
				# should delete htauth_c,time_by_ip,user db entry ...
				# &js_pw_login_part1();  # NOPE, wrong TARGET
				&delete_htauth_k($DAT{htauth_k}); &footer; exit 0;
			}
			$AUTH_USER = $DAT{htauth_u};
			my $mins = int (($time_from_db - time + $timeout)/60);

			# ------------------ on-going JS session :-) ---------------
			# We again assume that &tea_in_javascript resides in the FRAMESET
			# and the hidden_forms in the frame htauth_frame0 ... &output must
			# fiddle the ACTION= of forms in htauth_frame1 to invoke the JS.

			eval "require 'Crypt/Tea.pm';"; if ($@) {
				fatal ("can't require Tea.pm but htauth_t = $DAT{htauth_t} !");
			}
			import Crypt::Tea;

			# Decrypt htauth_t and insert contents into %DAT and the $CGI object
			my $htauth_p = &get_password($DAT{htauth_u});
			my %t = split /\0/, &Crypt::Tea::decrypt($DAT{htauth_t},$htauth_p);
			# but stray \0 at end ? doesn't seem to matter ...
			my ($k,$v); while (($k,$v)=each %t) {
				if ($k) { $DAT{$k}=$v; $CGI->param(-name=>$k,-value=>[$v]); }
			}
			&zap('htauth_t');

			# --------- JavaScript is running ; logout ? -------
			if ($DAT{htauth_x} eq 'logout') {
				undef $AUTH_USER;
				output <<EOT;
<P><CENTER><B>Login session finished.</B></CENTER></P>
<P><CENTER><A HREF="$ENV{SCRIPT_NAME}">
Restart $ENV{SCRIPT_NAME}</A>&nbsp;.&nbsp;.&nbsp;.</CENTER></P>
EOT
				# should delete htauth_c,time_by_ip,user db entry ...
				&delete_htauth_k($DAT{htauth_k}); &footer; exit 0;
			}

			# ------ JavaScript is running ; change password ? -----
			if ($DAT{htauth_x} eq 'change') {
				&set_password($dbdir, $DAT{htauth_u}, $DAT{htauth_p1});
				output <<EOT;
<CENTER><P>Welcome $DAT{htauth_u},
<B>your password has been changed.</B>
The session has $mins&nbsp;minutes remaining.
You may <A HREF="javascript:parent.htauth_logout();">log out</A>
if you wish.</P></CENTER>
EOT
				return 1;
			}

			# ------ JavaScript is running ; ongoing session :-) :-)
			output <<EOT;
<CENTER><P>Welcome $DAT{htauth_u}. There are $mins&nbsp;minutes remaining.
You may <A HREF="javascript:parent.htauth_logout();">log out</A>
if you wish.</P></CENTER>
EOT
			return 1;
		}

		# now we do the much simpler non-JavaScript case ...
		if ($DAT{htauth_u} && $DAT{htauth_k} && !$DAT{htauth_j}) {

			# ----------- JavaScript not running ; timeout ? -----------
			my $time_from_db = &check_htauth_k();
			if ($time_from_db < (time - $timeout)) {
				&zap('htauth_p','htauth_p1','htauth_p2','htauth_x','htauth_k');
				print <<'EOT';
<CENTER><B>Your last login has expired. Please log in again.</CENTER></B>
EOT
				&non_js_pw_login(); &footer; exit 0;
			}
			$AUTH_USER = $DAT{htauth_u};
			my $mins = int (($time_from_db - time + $timeout)/60);

			# --------- JavaScript not running ; logout ? -------
			if ($DAT{htauth_x} eq 'logout') { print <<EOT;
<CENTER><B>Login session finished.</B></CENTER><P>
<CENTER><A HREF="$ENV{SCRIPT_NAME}">
Restart $ENV{SCRIPT_NAME}</A>&nbsp;.&nbsp;.&nbsp;.</CENTER>
EOT
				&delete_htauth_k($DAT{htauth_k}); &footer; exit 0;
			}

			# --------- JavaScript not running ; change password ? -------
			if ($DAT{htauth_x} eq 'change') {  &change_password(); }

			# ----- JavaScript not running and an on-going session exists
			&zap('htauth_x'); my $query_string = &query_string(\%DAT);
			print <<EOT;
<P>This session has $mins minutes left.  You may
<A HREF="$ENV{SCRIPT_NAME}?$query_string&htauth_x=logout">
log out</A> if you wish.</P>
EOT
			return 1;   # Hooray !

		} else {   # check password and assign session key ...
			if (! &check_password($dbdir,$DAT{htauth_u},$DAT{htauth_p})) {
				&logit('login',"BadLogin $username");
				&zap('htauth_p','htauth_u');
				print <<EOT;
<B><CENTER>Sorry, wrong password.
Please try again&nbsp;.&nbsp;.&nbsp;.</CENTER></B>
EOT
				&non_js_pw_login(); &footer; exit 0;
			} else {   # password (htauth_p) was ok: assign a key (htauth_k)
				$DAT{htauth_k} = &remember_htauth_k();
				&logit('login', $username, 'plaintext password');
				my $mins = int ($timeout/60);
				&zap('htauth_p'); my $query_string = &query_string(\%DAT);
				$CGI->param(-name=>'htauth_k',-value=>$DAT{htauth_k});
				print <<EOT;
<P>Welcome $DAT{htauth_u}.  This session lasts for $mins&nbsp;minutes.
You may <A
HREF="$ENV{SCRIPT_NAME}?$query_string&htauth_k=$DAT{htauth_k}&htauth_x=change">
change your password</A> or <A
HREF="$ENV{SCRIPT_NAME}?$query_string&htauth_k=$DAT{htauth_k}&htauth_x=logout">
log out</A> if you wish.</P>
EOT
				return 1;   # Hooray !  Username/Password login has succeeded.
			}
		}

	} elsif ($auth_mode eq 'challenge') {
		&enter('htauth_u', 'Username :', size=>15, before=><<'EOT');
<B>Challenge-Response Authentication&nbsp;.&nbsp;.&nbsp;.</B>
EOT
		&end_form(); if ($INCOMPLETE) { &footer(); exit 0; }

		# do initial challenge-response
		my $ip = $ENV{REMOTE_ADDR};
		my $dbname  = "$dbdir/challenge/$DAT{htauth_u}";
		my $txtfile = "$dbdir/challenge/$DAT{htauth_u}.txt";
		my $curfile = "$dbdir/challenge/$DAT{htauth_u}.cur";

		# workaround for bug where dbmopen with 3rd arg=undef creates a new db
		if (! -f "$dbname.db" && ! -f "$dbname.dir" && ! -f "$dbname.pag") {
			&fatal("there are no passwords for $DAT{htauth_u}");
		}
		if (! dbmopen (%keys, $dbname, undef)) {
			&fatal("there are no passwords for $DAT{htauth_u}: $!");
		}
		my @keys = keys %keys;
		my $r;
		if (! $DAT{htauth_k}) {
			dbmclose %keys;
			my $keys_left = scalar @keys;
			# print "<P>keys_left = $keys_left</P>\n";
			if (! $keys_left) { &fatal("database empty"); }
			&setrand(); my $ri = int(rand($keys_left));
			$r = $keys[$ri+$[];
			# remember $r and IP, for later check
			if (!open(F,">$curfile")) { &fatal("can't open $curfile: \n"); }
			print F "$r $ip\n"; close F; chmod 0600, $curfile;
		}
		&enter('htauth_k', 'Password :', size=>15, before=><<EOT);
<P><B>Challenge-Response Authentication&nbsp;.&nbsp;.&nbsp;.</B></P>
<P><B>Enter password number $r for $DAT{htauth_u}:</B></P>
EOT
		&end_form(keys %DAT);   # preserves all the rest of %DAT
		if ($INCOMPLETE) { &footer(); exit 0; }

		# check htauth_u and htauth_k for valid key; retrieve $r from the curfile
		if (! open(F,"< $curfile")) { &fatal("can't open $curfile: $!"); }
		my ($r_and_ip, $r, $previousip);
		$r_and_ip = <F>; close F;
		$r_and_ip =~ s/\s*$//;
		($r, $previousip) = split (' ',$r_and_ip);
		if ($previousip ne $ENV{REMOTE_ADDR}) {
			&fatal("IP address changed $previousip to $ENV{REMOTE_ADDR}"); 
		}
	
		if ($DAT{htauth_k} eq $keys{$r}) {
			if (($#keys-$[+1) < ($nkeys/10)) { # are the keys 90% used yet ? XXX
				if (&'confirm("Your keys are almost used up; make another set ?")){
					dbmclose %keys; &make_keys($dbdir, $DAT{htauth_u});
				} else {
					delete $keys{$r}; dbmclose %keys;
				}
			} else {
				delete $keys{$r}; dbmclose %keys;
			}
			&forget_hidden_values('htauth_k');
			output "<P>Welcome $DAT{htauth_u}, you have been authenticated.</P>\n";
			return 1;   # Hooray !  Challenge-response was OK.
		} else {
			delete $keys{$r}; dbmclose %keys; &fatal(
			"For $DAT{htauth_u} key $r, $DAT{htauth_k} is the wrong response.");
		}
	}
}

# ---------------- general infrastructure --------------------

# local versions of subroutines sorry, fatal, footer, timestamp and output
sub sorry {
	if (defined &main::header && ! $header_already) {
		&main::header ("Sorry . . .");
	} elsif (! $header_already) {
		output <<EOT;
Content-type: text/html

<HTML><HEAD><TITLE>Sorry . . .</TITLE></HEAD>
EOT
		output '<BODY';
		if ($bgcolor) { output " BGCOLOR=\"$bgcolor\""; }
		if ($fgcolor) { output " TEXT=\"$fgcolor\""; }
		output "><HR>\n";
	}
	output '<CENTER><B>Sorry, ', $_[$[], '</B></CENTER>'; &footer();
}
sub fatal { &sorry ($_[$[]); exit 0; }
sub footer {
	if (defined &main::footer) { &main::footer;
	} else { output "<HR></BODY></HTML>\n";
	}
}
sub timestamp {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	sprintf ("%4.4d%2.2d%2.2d %2.2d%2.2d%2.2d",
	$year+1900, $mon+1, $mday, $hour, $min, $sec);
}
sub query_string {  my $hashref = shift;
	my @query_string = ();  my $k; my $v;
	foreach $k (keys %$hashref) {
		$v = $$hashref{$k};
		$k =~ s/(\W)/sprintf("%%%x", ord($1))/eg;
		$v =~ s/(\W)/sprintf("%%%x", ord($1))/eg;
		push @query_string, "$k=$v";
	}
	return join('&', @query_string);
}
sub zap {   # CGI->param and CGI->delete both crash if value isn't there :-(
	if (! defined $CGI) { &fatal('zap: $CGI not defined'); }
	foreach (@_) { eval { $CGI->delete($_); }; delete $DAT{$_}; }
}
sub str2js {
	my @lines = split (/\n/, join ('', @_));
	foreach (@lines) { s/\\/\\\\/g; s/'/\'/g; s/^/ '/; s/$/\\n'/; }
	return join (" +\n", @lines);
}

sub ip_matches { my ($ip, $patterns) = @_;   # pattern can include *
	if (! $patterns) { return 0; }
	my @patterns = split ' ', $patterns;
	foreach $pattern (@patterns) {
		$pattern =~ s/\./\\./g;
		$pattern =~ s/\*/\\d+/g;
		if ($ip =~ /^$pattern$/) { return 1; }
	}
	return 0;
}
sub javascript_supported {
	my $browser = $ENV{HTTP_USER_AGENT};
	if ($browser =~ /Lynx/) { return 0; }
	if ($browser =~ /Mozilla\/1\.0/) { return 0; }
	return 1;
}
sub test_and_make {  my $dir = $_[$[];  # makes dir if it doesn't exist
	if (!-d $dir) { if (!mkdir $dir,0750) {&fatal("can't mkdir ${dir}: $!");} }
}
sub logit { # &logit('login', $username);  # perhaps a logdir in config ?
	return 1;
}

# ----------- infrastructure for username/password ---------------

sub non_js_pw_login {
	&zap('htauth_p');
	my $form3 = CGI::FormBuilder->new(
		method => 'POST', params => $CGI, name => 'htauth_form4',
		keepextras => 1, required => 'ALL',
		fields => [qw/htauth_u htauth_p/],
		labels => { htauth_u=>'Username', htauth_p=>'Password' },
		reset => 0, submit => 'Login',
	);
	$form3->field(name=>'htauth_p',type=>'password');
	print '<CENTER>',$form3->render,"</CENTER>\n"; &footer; exit 0;
}
sub js_pw_login_part1 {
	# BUG must forcibly preserve all _submitted_* variables from FormBuilder...
	# foreach ($CGI->param()) { output "$_ = ", $CGI->param($_), "<BR>\n"; }
	my $form5 = CGI::FormBuilder->new(
		method=>'POST', params=>$CGI, name=>'htauth_form6',
		keepextras=>1, required=>'ALL',
		fields => [qw/htauth_u htauth_j/], labels => { htauth_u=>'Username' },
		submitted=>'htauth_u', reset=>0, submit=>'Login',
	);
	$form5->field(name=>'htauth_j',type=>'hidden');
	output '<CENTER>',$form5->render, <<'EOT';
</CENTER><SCRIPT LANGUAGE="JavaScript"><!--
document.htauth_form6.htauth_j.value = 'yes';
// -->
</SCRIPT>
EOT
}

sub js_pw_login_part2 {
	# We now print a frameset, to contain the encryption engine and
	# remember htauth_p. Underneath is a thin top frame, htauth_frame0,
	# containing the hidden form, and the main frame htauth_frame1.
	# The calling application may already have written at least the
	# header of the current document, so we insist on using &output
	# and store all that stuff (if ($DAT{htauth_u} && $DAT{htauth_j}
	# && !$DAT{htauth_r})) and output it into the main frame :-)
	# Here we use a hardcoded HTML form, not FormBuilder

	# strip the header, quote the rest, add it to load_frame1 ....
	my $body = join '', @to_be_output;
	$body =~ s/^.*<BODY/<BODY/is;
	my $body_in_js = &str2js($body);
	@to_be_output = ();

	eval "require 'Crypt/Tea.pm';"; if ($@) { &fatal(<<'EOT');
we shouldn't have reached here unless Crypt::Tea.pm was installed :-( $@
EOT
	}

	# The challenge is set in the ACTION url in subframe htauth_frame1
	print <<'EOT', &Crypt::Tea::tea_in_javascript();
Content-type: text/html

<HTML><HEAD><TITLE>Login with security by CGI::Htauth.pm</TITLE>
EOT
	print <<'EOT';
<SCRIPT LANGUAGE="JavaScript"><!--
// and this bit comes from the CGI::Htauth.pm module ...
function decrypt_and_write(ascii) {
 htauth_frame1.document.write(decrypt(ascii, remember_htauth_p));
 htauth_frame1.document.close();
}
keep_in_plaintext = new Object();  // to preserve pre-authenticated app vars
keep_in_plaintext['htauth_u'] = true;
keep_in_plaintext['htauth_r'] = true;
keep_in_plaintext['htauth_t'] = true;

function respond_and_login(form) {
 remember_htauth_p   = form.htauth_p.value;  // global
 htauth_frame0.document.htauth_form0.htauth_r.value =
  asciidigest(form.htauth_c.value + remember_htauth_p);
 htauth_frame0.document.htauth_form0.submit();
 return one_moment_please();
}
function encrypt_and_submit(form) { // nb: javascript: url passes the frame
 var plaintext = '';
 for (var i=0; i<form.length; i++) {
  var e = form.elements[i];
  if (!keep_in_plaintext[e.name]) { plaintext += (e.name+"\0"+ e.value+"\0"); }
 }
 htauth_frame0.document.htauth_form0.htauth_r.value = '';
 htauth_frame0.document.htauth_form0.htauth_t.value =
  encrypt(plaintext, remember_htauth_p);
 htauth_frame0.document.htauth_form0.submit();
 return one_moment_please();
}
// XXX BUG because this zaps preauthenticated vars, &authenticate isn't called.
function htauth_logout () {
 htauth_frame0.document.htauth_form2.htauth_t.value =
  encrypt('htauth_x\0logout', remember_htauth_p);
 remember_htauth_p = '';
 htauth_frame0.document.htauth_form2.submit();
 return one_moment_please();
}

function submit_htauth_change (form) {
 var password = form.elements['password'].value;
 if ( (! password.match(/^\S{6,20}$/)) ) {
  alert('Error:  Password must be 6 or more\nnon-space characters');
  return false;
 }
 var confirm_password = form.elements['confirm_password'].value;
 if ( ! (confirm_password == form.password.value)) {  // need onSubmit ?
  alert('Error: The two Password fields did not match');
  return false;
 }
 htauth_frame0.document.htauth_form0.htauth_r.value = '';
 htauth_frame0.document.htauth_form0.htauth_t.value =
  encrypt('htauth_x\0change\0htauth_p1\0'+password, remember_htauth_p);
 htauth_frame0.document.htauth_form0.submit();
 remember_htauth_p = password; // hope the change will succeed on the server ..
 return one_moment_please();
}
function htauth_change () {
 var body = '<BODY';
 var bg = htauth_frame1.document.bgColor;
 if (bg) { body += ' BGCOLOR="' + bg + '"'; }
 var fg = htauth_frame1.document.fgColor;
 if (fg) { body += ' TEXT="' + fg + '"'; }
 body += '>';

 htauth_frame1.document.write (
  '<HTML><HEAD><TITLE>CGI::Htauth.pm</TITLE></HEAD>\n' + body +
  '<P><CENTER><B>Changing Password for ' +
  htauth_frame0.document.htauth_form0.htauth_u.value +
  '&nbsp;.&nbsp;.&nbsp;.</B></CENTER></P><P><CENTER><form method="POST" ' +
'action="javascript:parent.submit_htauth_change(this.document.forms[0]);">\n'+
  '<table><tr><td align="left"><b>New Password</b></td>\n' +
  '<td><input name="password" type="password"></td></tr>\n' +
  '<tr><td align="left"><b>Confirm Password</b></td>\n' +
  '<td><input name="confirm_password" type="password"></td></tr>\n' +
  '<tr><td colspan="2"><center>\n' +
  '<input name="reset" type="reset" value="Clear">\n' +
  '<input name="submit" type="submit" value="Change Password">\n' +
  '</center></td></tr></table></form></CENTER></BODY></HTML>\n'
 );
}
function one_moment_please () {
 var returnstr = '<BODY';
 var bg = htauth_frame1.document.bgColor;
 if (bg) {
  htauth_frame0.document.htauth_form0.htauth_bg.value = bg;
  htauth_frame0.document.htauth_form1.htauth_bg.value = bg;
  returnstr += ' BGCOLOR="' + bg + '"';
 }
 var fg = htauth_frame1.document.fgColor;
 if (fg) {
  htauth_frame0.document.htauth_form0.htauth_fg.value = fg;
  htauth_frame0.document.htauth_form1.htauth_fg.value = fg;
  returnstr += ' TEXT="' + fg + '"';
 }
 return returnstr + '><CENTER>One moment please . . .</CENTER></BODY>';
}

function load_frame0(w) {
 w.document.write (
 '<HTML><HEAD><TITLE>frame_0</TITLE><BODY>\n' +
EOT
	# need 3 forms: to submit, to retry, to logout
	my %dat = %DAT;
	delete $dat{htauth_r}; delete $dat{htauth_t};
	print &hidden_form('htauth_form0','htauth_frame1',   # encrypt and submit
		'htauth_u',$DAT{htauth_u}, 'htauth_j','yes', 'htauth_r','',
		'htauth_bg',$DAT{bgcolor}, 'htauth_fg',$DAT{fgcolor},
		'htauth_k','' ,'htauth_t','',%dat);
	print &hidden_form('htauth_form2','_parent',   # logout
		'htauth_u',$DAT{htauth_u}, 'htauth_j','yes', 'htauth_r','',
		'htauth_bg',$DAT{bgcolor}, 'htauth_fg',$DAT{fgcolor},
		'htauth_k','' ,'htauth_t','',%dat);
	delete $dat{htauth_u}; delete $dat{htauth_j};
	print &hidden_form('htauth_form1','_parent','htauth_k','',
		'htauth_bg',$DAT{bgcolor}, 'htauth_fg',$DAT{fgcolor},%dat);  # retry
	print <<'EOT';
 '</BODY></HTML>\n'
 );
}
function load_frame1(w) {
 w.document.write (
'<HTML><HEAD><TITLE>CGI::Htauth.pm</TITLE></HEAD>\n' +
EOT
	my $htauth_c = &generate_htauth_c();
	print <<EOT;
$body_in_js +
'<BR>&nbsp;<BR><CENTER><B>Welcome, $DAT{htauth_u}.<BR>&nbsp;<BR>\\n' +
'Please enter your Password&nbsp;.&nbsp;.&nbsp;.</B><BR>&nbsp;<BR>\\n<form ' +
'action="javascript:parent.respond_and_login(document.htauth_form5);" ' +
'method="POST" name="htauth_form5">\\n' +
'<input name="_sessionid" type="hidden" value="">\\n' +
'<input name="htauth_c" type="hidden" value="$htauth_c">\\n' +
'<b>Password</b> <input name="htauth_p" type="password">\\n' +
'<input name="_submit" type="submit" value="Login"> </form>\\n' +
'<BR>Your password will not get transmitted onto the Net :-)</CENTER>\\n' +
'<BR><HR></BODY></HTML>\\n'
 );
}
// -->
</SCRIPT>
</HEAD><FRAMESET ROWS="2%,98%" COLS="100%">
<FRAME NAME="htauth_frame0" FRAMEBORDER=0 MARGINHEIGHT=1
SRC="javascript:parent.load_frame0(window);">
<FRAME NAME="htauth_frame1" FRAMEBORDER=0 MARGINHEIGHT=1
SRC="javascript:parent.load_frame1(window);">
</FRAMESET></HTML>
EOT
	exit 0;
}

sub hidden_form {  my ($name, $target, @var_val) = @_;
	my @html = (); my $var; my $val; my %seen;
	push @html, "<FORM NAME=\"$name\" ACTION=\"$ENV{SCRIPT_NAME}\" ";
	push @html, "METHOD=\"POST\" TARGET=\"$target\">";
	while (@var_val) {
		$var = shift @var_val; $val = shift @var_val;
		next if $var eq 'submit'; # avoid FormBuilder trashing JS form.submit()
		if (! $seen{$var}) {   # first occurence takes precedence.
			#  BUG: must encode $var and $val !!
			push @html, "<INPUT TYPE=\"hidden\" NAME=\"$var\" VALUE=\"$val\">";
			$seen{$var} = 1;
		}
	}
	push @html, "</FORM>' +\n";
	return "   '". (join "' +\n   '", @html);
}

sub change_password {
	my $text = '';
	if (! $DAT{htauth_p1} || !$DAT{htauth_p2}){
		$text = "Changing Password for $DAT{htauth_u}&nbsp;.&nbsp;.&nbsp;.";
	} elsif ($DAT{htauth_p1} ne $DAT{htauth_p2}) {
		$text = "The two entries must be the same&nbsp;.&nbsp;.&nbsp;.";
	} elsif (length $DAT{htauth_p1} < 5) {
		$text = "Choose a longer password (5 chars min)&nbsp;.&nbsp;.&nbsp;.";
	}
	if ($text) {
		my $f5 = CGI::FormBuilder->new(
			text=>"$text", keepextras=>1, required=>'ALL',
        	method=>'POST', params=>$CGI, name=>'f5',
        	fields => [qw/htauth_x htauth_p1 htauth_p2/],
        	labels => {
				htauth_p1=>'New password :', htauth_p2=>'New password (again):'
			},
        	reset => 0, submit => 'Change Password',
     	);
		$f5->field(name=>'htauth_x',type=>'hidden',value=>'change');
     	$f5->field(name=>'htauth_p1',type=>'password');
     	$f5->field(name=>'htauth_p2',type=>'password');
      output '<CENTER>',$f5->render,"</CENTER>\n"; &footer; exit 0;
	}
	# security ? what if we're just fed the vars in a url ?
	&set_password($dbdir, $DAT{htauth_u}, $DAT{htauth_p1});
	&zap('htauth_p1','htauth_p2','htauth_x');
	output <<EOT;  # mins ?
<CENTER><P>Password changed for $DAT{htauth_u}.
This session has $mins&nbsp;minutes remaining.
You may <A HREF="javascript:parent.remember_htauth_p = '';
parent.submit_htauth_x('logout');">log out</A> if you wish.</P></CENTER>
EOT
}
sub bad_password1 {
	my $p1 = $DAT{htauth_p1}; my $p2 = $DAT{htauth_p2};
	if ($p1 ne $p2) { return "Passwords must match"; }
	if ((length $p1) < 4) { return "Minimum 4 chars"; }
	return '';
}
sub bad_password2 {
	my $p1 = $DAT{htauth_p1}; my $p2 = $DAT{htauth_p2};
	if ((length $p2) < 4) { return "Minimum 4 chars"; }
	if ($p1 ne $p2) { return "Passwords must match"; }
	return '';
}
sub get_password { my $username=shift;
	if (! $dbdir)    { &fatal ("Htauth::get_password: dbdir not set."); }
	if (! $username) { &fatal ("Htauth::get_password: username not set."); }
	if (! dbmopen (%DB, "$dbdir/password/passwd_by_user", 0640)) {
		&fatal ("can't dbmopen $dbdir/password/passwd_by_user: $!");
	}
	my $password = $DB{$username}; dbmclose %DB; return $password;
}
sub check_password { $dbdir=shift; my $username=shift; my $password=shift;
	if (!$username || !$password) { return 0; }
	if (! dbmopen (%DB, "$dbdir/password/passwd_by_user", 0640)) {
		&fatal ("can't dbmopen $dbdir/password/passwd_by_user: $!");
	}
	if ($DB{$username} eq $password) { dbmclose %DB; return 1;
	} else { dbmclose %DB; return 0;
	}
}
sub set_password { my $dbdir=shift; my $username=shift; my $password=shift;
	return unless $username;
	&test_and_make($dbdir);
	&test_and_make("$dbdir/password");
	if (! dbmopen (%DB, "$dbdir/password/passwd_by_user", 0640)) {
		&fatal ("can't dbmopen $dbdir/password/passwd_by_user: $!");
	}
	$DB{$username} = $password;
	dbmclose %DB;
}

# stuff concerned with the htauth_c JS login challenge
sub generate_htauth_c { # Issue a challenge for use in JS session
	my $htauth_c = &random_key(); # generate a key
	my $k_t = "$htauth_c," . &timestamp();
	my $db  = "$dbdir/password/htauth_c,time_by_ip,user";
	my $i_u = "$ENV{REMOTE_ADDR},$DAT{htauth_u}";
	if (! dbmopen(%DB,$db,0640)) { &fatal("Can't dbmopen $db: $!"); }
	$DB{$i_u} = $k_t; dbmclose %DB;   # no lock, therefore speed ...
	return $htauth_c;
}
sub get_htauth_c_time {
	my (%DB); my $db = "$dbdir/password/htauth_c,time_by_ip,user";
	my $i_u = "$ENV{REMOTE_ADDR},$DAT{htauth_u}";
	if (! dbmopen (%DB,$db,undef)) { &fatal("Can't dbmopen $db: $!"); }
	my $k_t = $DB{$i_u}; dbmclose %DB; return split /,/, $k_t;
}
sub delete_htauth_c_time {
	my (%DB); my $db  = "$dbdir/password/htauth_c,time_by_ip,user";
	my $i_u = "$ENV{REMOTE_ADDR},$DAT{htauth_u}";
	if (!dbmopen(%DB,$db,0640)) { return 0; }
	delete $DB{$i_u}; dbmclose %DB;   # no lock, therefore speed ...
}

# stuff concerned with the htauth_k session key
sub check_htauth_k {
	my (%DB); my $db = "$dbdir/password/user,time_by_htauth_k";
	if (! dbmopen (%DB, $db, undef)) { &fatal ("Can't dbmopen $db: $!"); }
	my $name_and_time_from_db = $DB{$DAT{htauth_k}};
	dbmclose %DB;
	if (!$name_and_time_from_db) {
		&fatal("No current login, k=$DAT{htauth_k}");
	}
	my ($name_from_db,$time_from_db)=split(' ',$name_and_time_from_db);
	if ($name_from_db ne $DAT{htauth_u}) {
		&fatal ("The key in your URL does not fit your username.");
	}
	return $time_from_db;
}
sub remember_htauth_k {
	# we just give them a random key in their url, to which they can return
	my (%DB, $random_key); my $db = "$dbdir/password/user,time_by_htauth_k";
	if (! dbmopen (%DB, $db, 0640)) { &fatal ("can't dbmopen $db: $!"); }
	$htauth_k = &random_key();
	$DB{$htauth_k} = "$DAT{htauth_u} ".time;
	dbmclose %DB;
	return $htauth_k;
}
sub delete_htauth_k { my $htauth_k = shift;
	my %DB; my $db = "$dbdir/password/user,time_by_htauth_k";
	if (! dbmopen (%DB, $db, 0640)) { &fatal ("can't dbmopen $db: $!"); }
	delete $DB{$htauth_k};
	dbmclose %DB;
}
sub random_key {
	my $t = time(); my $pid = $$; my $p = $pid; my $buf;
	if (open(P, 'df|')) {
		while (read P, $buf, 4) {
			$buf =~ /(.)(.)(.)(.)/;
			$p ^= ((ord($1)<<21) + (ord($2)<<14) + (ord($3)<<7) + ord($4));
		}
		close P;
	}
	my $r = $t ^ $p ^ (($pid<<20) + ($pid<<10) + $pid);
	return "$r";
}

# ----------- infrastructure for challenge/response ---------------

sub setrand {
	local ($a,$b,$c,$d) = times;
	$a=int($a*60); $b=int($b*60); $c=int($c*60); $d=int($d*60);
	local ($salt) = int ($$<<16 ^ $a<<12 ^ $b<<8 ^ $c<<4 ^ $d);
	srand (time ^ $salt);	# should also use df, netstat, iostat, uptime, ps
}

sub randomkey { local ($length) = @_; $length = 6 unless $length;
	local(@c)=('a'..'k','m'..'z','0','2'..'9','=','-');
	local ($i, @key);
	for ($i=1; $i<=$length; $i++) { push (@key, $c[int(rand($#c-$[))]); }
	join ('', @key);
}

sub make_keys { my ($dbdir, $htauth_u) = @_;
	if (! $htauth_u) { &fatal("make_keys called with no username"); }
	my $dbname  = "$dbdir/challenge/$htauth_u";
	my $txtfile = "$dbdir/challenge/$htauth_u.txt";
	my $curfile = "$dbdir/challenge/$htauth_u.cur";

	&test_and_make ("$dbdir/challenge");
	unlink ("${dbname}.dir", "${dbname}.pag", "${dbname}.db");
	unlink ($txtfile, $curfile);
	if (! dbmopen(%keys, $dbname, 0600)) {
		&fatal("make_keys can't dbmopen $dbname: $!\n");
	}
	&setrand(); for ($i=0; $i<$nkeys; $i++) { $keys{$i} = &randomkey(6); }
	local (@keys) = keys (%keys);
	my $timestamp = &timestamp;
	local ($text) = <<"EOT";
\r
       $htauth_u                                             $timestamp\r
\r
\r
       0      1      2      3      4      5      6      7      8      9\r
EOT
	for ($i=0; $i<$nkeys; $i++) {
		if ($i && ! ($i%50)) { $text .= "\r\n"; }
		if (! ($i%10)) { $text .= sprintf("\r\n%3d ", $i); }
		$text .= " "; $text .= $keys{$i};
	}
	dbmclose %keys;
	$text .= <<EOT;
\r
\r
       0      1      2      3      4      5      6      7      8      9\f
EOT
	if (!open(F,"> $txtfile")) { &fatal("can't open $txtfile: $!"); }
	chmod (0600, $txtfile);
	print F $text; close F;
	system "lpr $txtfile";  # XXX must offer choice of printers
	return 1;
}

sub printers {
	my @printers;
	if (-r "/etc/printcap" && open (F, "< /etc/printcap")) {
		while (<F>) { if (/^([-\w]+)/) { push (@printers, $1) } }  
		close F;
	} elsif (open (F, "lpstat -a |")) { # SysV
		while (<F>) { if (/^([-\w]+)\s/) { push (@printers, $1) } }
		close F;
	}
	sort @printers;
}

1;

__END__

=pod

=head1 NAME

CGI::Htauth.pm - Authentication services for CGI scripts.

=head1 SYNOPSIS

	use CGI;              # Sadly, CGI::Minimal is not enough
	use CGI::FormBuilder; # usually; Htauth will use it anyway
	use CGI::Htauth;      # :-)

	my $CGI = new CGI;    # necessary when using Htauth
	&initialise_htauth($CGI);  # before any text gets output !

	&header($CGI->param('maintask') || $ENV{SCRIPT_NAME});

	&authenticate(<<EOT);
	dbdir /var/run/htauth
	allow 127.0.0.1                   # trust localhost logins
	deny 10.0.123.*                   # lock out Sales PCs
	password 10.*.*.* timeout=900     # password login on local net
	challenge 123.234.*.* timeout=600 # for Sydney office
	challenge *.*.*.* timeout=0       # just useable for travellers
	EOT

	if ($AUTH_USER eq 'fred') {
	  # fred has logged in by password or challenge-response ...
	  my $form = CGI::FormBuilder->new(
	    params => $CGI,   # necessary when also using Htauth !
	    keepextras => 1,  # necessary when also using Htauth !
	    method => 'POST', # necessary when also using Htauth !
	    fields => [qw(thisfield thatfield theotherfield email)],
	    validate => {email => 'EMAIL'},
	  );
	  if (!$form->submitted || !$form->validate) {
	    &output($form->render);  # Must use output not print !
	    &footer();
	  }
	  &do_fred_stuff();
	} else {
	  &do_other_stuff();
	}

	sub header {
	  output "<HTML><HEAD><TITLE>$_[$[]</TITLE></HEAD><BODY>\n";
	}
	sub footer {
	  output "<HR></BODY></HTML>\n";
	}

=head1 DESCRIPTION

This Perl library provides authentication services useable by CGI scripts.
Several levels of authentication can be imposed,
depending on the IP address or hostname of the client.

Then authentication is performed by calling the subroutine I<authenticate>
according to a configuration specified its argument.

The calling program must unfailingly use I<output> instead of the usual
I<print> so that I<Htauth> can encrypt the HTML text if necessary.
The calling program must also call I<&initialise_htauth($CGI);> before
any text is output, so that I<Htauth> knows whether to print the
text immediately or to save it up for later encryption.
If the calling program uses CGI::FormBuilder,
the options "params => $CGI", "keepextras => 1" and method => 'POST'
must always be present.
It is not essential, but will make presentation slicker, if the calling
program has subroutines (in package main) called I<&header($title)> and
I<&footer> to output (using I<output>, remember...) the HTML header and footer.

CGI::Htauth.pm uses CGI.pm (CGI::Minimal.pm lacks the I<delete> method),
uses Crypt::Tea.pm in order to communicate securely with
JavaScript-capable browsers,
and uses CGI::FormBuilder.pm to manage the data entry.
Very often the cgi programmer will be using CGI::FormBuilder.pm anyway,
to write the application.

Version 1.21,
#COMMENT#

=head1 SUBROUTINES

=over 3

=item I<initialise_htauth>( $CGI );

The argument I<$CGI> is a reference to a CGI object.
This must be called before any text is output
to inform I<Htauth> of the state of the parameters.

=item I<authenticate>( $config_txt, $CGI );

The argument $config_txt is either a multiline text string,
or the name of a file containing such a string.
IP addresses (indicated as IPADDR) may contain *
which matches any string of up to three digits.
The second argument is again the reference to the CGI object.

The first config line that matches the client IP address $ENV{REMOTE_ADDR}
will determine the type of authentication to which the client is subject.
If the user has logged in, either by password or by challenge-response,
then the (exported) Perl variable $AUTH_USER is set to the username.


=over 5

=item I<allow IPADDR>

Access will be allowed from any IP address matching the $ip pattern.

=item I<deny IPADDR>

Access will be denied from any IP address matching the $ip pattern.

=item I<password IPADDR timestamp=1800>

Access from any IP address matching the $ip pattern is met with a
Username-and-Password login request.
This data travels over the network in cleartext (unless you are using https).
If the Password is valid, then a temporary session key is generated,
which is passed back to the next invocation by hidden form variables.

This routine uses various FORM variables beginning with I<htauth_>
and applications would be wise to avoid creating FORM variables
beginning with I<htauth_> as these may produce Unpredictable Consequences.

=item I<challenge IPADDR timestamp=0>

Access from any IP address matching the $ip pattern is met with a
Username request and a One-time-key challenge.
This data travels over the network in cleartext (unless you are using https).
If the Password is valid, then a temporary session key is generated,
which is passed back to the next invocation by hidden form variables.
A new temporary session key is generated every invocation,
so the user will not be able to use the browser's I<Back> key.

If the session is within 30 seconds of timing out,
a new One-time-key challenge is issued instead.
Thus setting the timeout to less than 30 seconds (e.g. to 0, the default)
causes a One-time-key challenge to be issued on every page.

This routine uses various FORM variables beginning with I<htauth_>
and applications would be wise to avoid creating FORM variables
beginning with I<htauth_> as these may produce Unpredictable Consequences.

=back

=item I<set_password> ( $dbdir, $username, $password );

The argument $dbdir is the directory in which the password
databases will be set up.
If it doesn't exist, it should be createable.
It must be writeable by the httpd user, eg I<nobody> or I<wwwrun>.

The argument $username is the Htauth-username whose password is to be changed.
This username will be created if it doesn't yet exist.

The argument $password is the new password.

=head1 RESERVED WORDS

Like everything on the web, I<CGI::Htauth.pm> must do its
stuff by manipulating frames, forms and query variables.
The names it reserves for its own use all begin with I<htauth_> so
applications should avoid creating frames, forms, query variables
or JavaScript variables or methods beginning with I<htauth_>
as these may have Unpredictable Consequences.

=over 3

=item I<htauth_frame0>

is the almost invisible top frame
which occurs in JavaScript login; it contains nothing but the
hidden forms I<htauth_form0> (to submit),
I<htauth_form1> (to log in again) and
I<htauth_form2> (to log out)

=item I<htauth_frame1>

is the main frame
which occurs in JavaScript login; it contains the application
as seen by the user.

=item I<htauth_form0>

is the hidden form which is filled out
by JavaScript with the encrypted data I<htauth_t> and the
response I<htauth_r>, and is really submitted when the user thinks
they're submitting the application form visible in I<htauth_frame1>.
This form is also used, with I<htauth_x> = I<change>, to change password.

=item I<htauth_form1>

is the hidden form with a TARGET of the
main (parent) FRAMESET, which causes Htauth to ask for a new login.

=item I<htauth_form2>

is the hidden form with a TARGET of the main (parent) FRAMESET,
which logs the user out and restarts the entire script with no variables.

=item I<htauth_form4>

is the form used during
non-JavaScript login which asks for username and password.

=item I<htauth_form5>

is the form in I<htauth_frame1> which just asks for
username, used during login on a JavaScript-capable browser;
it also sniffs to see is JavaScript is enabled.

=item I<htauth_j>

is a sniffer variable,
which the browser sets to 'yes' if JavaScript is actually enabled.

=item I<htauth_form6>

is the form which just asks for password,
residing in I<htauth_frame1> and
used during password login on a JavaScript-enabled browser 

=item I<htauth_u> is the htauth Username

=item I<htauth_p>

is a Password as entered by user;
it only gets transmitted to the server if the user
does not have a JavaScript-enabled browser.

=item I<htauth_c>

is the challenge issued by the server
during the JavaScript password login dialogue.

=item I<htauth_k>

is a Session Key, generated at login by Htauth,
which is used during a login session.

=item I<htauth_r>

is the browser's Response to a challenge by the server;
it is used both during challenge-response login,
and during the JavaScript password login dialogue.

=item I<htauth_t>

is stuff encrypted by Crypt::Tea in the browser

=item I<htauth_x>

is a hold-all for other commands
such as change password, log out, etc etc

=item I<htauth_bg>

is used during a JavaScript login session;
it is set to the document BGCOLOR by JavaScript in the browser,
and is used by Htauth to set a background colour for all its
dialogue which fits the decor of the application.

=item I<htauth_fg>

is likewise set to the document TEXT by JavaScript in the
browser, and is used by Htauth to set a foreground colour for its dialogues.

=back

=head1 FUTURE DEVELOPMENTS

Currently challenge-response is not really implemented.

Several more config directives are tempting, for example:
some built-in way of insisting on a minimum password length,
I<logdir> to allow logging of logins and logouts,
perhaps other modes to specify use of Crypt::Tea during login
for security but then an unencrypted session to lighten the CPU load on the
server, or to allow only JavaScript browsers so that the password
can never be betrayed.

Perhaps for a session, the challenge could be used
together with the password as the encryption key,
to make cryptanalyisis harder for someone prepared to sniff
multiple login sessions.

User admin functions could be much more pre-packaged and complete.

=head1 AUTHOR

Peter J Billam <computing@pjb.com.au>

=head1 CREDITS

Based on and older module called I<htauth.pm> which
used I<htui.pm> to handle the user interface, instead of
Nathan Wiger's I<CGI::FormBuilder.pm>.
Thanks also to Neil Watkiss for MakeMaker packaging.

=head1 SEE ALSO

http://www.cpan.org/SITES.html, http://www.pjb.com.au/,
CGI.pm, CGI::FormBuilder.pm, Crypt::Tea.pm, perl(1).

=cut

