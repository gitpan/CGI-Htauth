use ExtUtils::MakeMaker;

WriteMakefile(
    NAME		=> 'CGI::Htauth',
    VERSION_FROM	=> 'Htauth.pm',
    PREREQ_PM		=> {
	'Crypt::Tea'		=> 0,
	'CGI'			=> 0,
	'CGI::FormBuilder'	=> 0,
    },
);
