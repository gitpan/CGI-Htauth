#! #PERLBIN#
# VERSION #VERSION#
use CGI; use CGI::FormBuilder; use CGI::Htauth;

my $CGI = new CGI; # must be here so both FormBuilder & Htauth have access
&initialise_htauth($CGI);  # must be here, before anything gets output.

my %DAT; foreach ($CGI->param()) { $DAT{$_} = $CGI->param($_); }

&header($DAT{main_task} || "$ENV{SCRIPT_NAME} version #VERSION#");

my $form1 = CGI::FormBuilder->new(
	params => $CGI, keepextras => 1, name=>'form1', method=>'POST',
	text => "<P>This is the public bit, before &authenticate gets called.</P>",
	fields => [qw(favourite_motto main_task)],
	required => 'ALL',
);
$form1->field(
	name=>'main_task', options=>['allow','deny','username/password']
);
# must not use plain ->submitted() because FormBuilder zaps _submitted_*
if (!$form1->submitted('main_task') || !$form1->validate) {
	output '<CENTER>',$form1->render,"</CENTER>\n"; &footer();
}

my $config;
if ($DAT{main_task} eq 'allow') { $config = <<EOT;
dbdir /tmp/htauth
allow 127.0.0.1
EOT
} elsif ($DAT{main_task} eq 'deny') { $config = <<EOT;
dbdir /tmp/htauth
deny 127.0.0.1
EOT
} elsif ($DAT{main_task} eq 'username/password') { $config = <<EOT;
dbdir /tmp/htauth
password 127.0.0.1 timeout=300
EOT
} else { print "Sorry, unrecognised main_task $DAT{main_task}"; &footer;
}
&authenticate ($config, $CGI);

my $form2 = CGI::FormBuilder->new(
	params   => $CGI, keepextras => 1, name=>'form2', method=>'POST',
	text => "<P>This is the private, in-house bit.</P>",
	fields   => [qw(security_level private_email account_number launch_code)],
	validate => {private_email => 'EMAIL'},
);
if (!$form2->submitted || !$form2->validate) {
	output '<CENTER>',$form2->render,"</CENTER>\n"; &footer();
}

my $fields = $form2->field;      # get all fields as hashref
output "The private, in-house fields are . . .<BR>\n";
foreach (sort keys %$fields) { output "$_ = $$fields{$_}<BR>\n"; }
&footer();

sub header {
	output <<EOT;
Content-type: text/html

<HTML><HEAD><TITLE>$_[$[]</TITLE></HEAD><BODY BGCOLOR="#FFFFFF"><HR>
EOT
	if ($ENV{HTTP_USER_AGENT} !~ /Lynx/) { output "<H1>$_[$[]</H1>"; }
	if (%DAT) {
		foreach (sort keys %DAT) { output "$_ = $DAT{$_}<BR>\n"; }
		output "<HR>\n";
	}
}
sub footer { output "<HR></BODY></HTML>\n"; exit 0; }
