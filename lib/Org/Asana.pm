package Org::Asana;

# https://github.com/mengwong/org-asana/

use Moose;
use WWW::Asana;
use YAML qw(LoadFile DumpFile);
use Carp;
use File::Path;

has 'verbosity'        => (is=>'rw',isa=>'Num',default=>0);

sub verbose {
	my $self = shift;
	return if not $self->verbosity;
	printf STDERR @_;
	print "\n";
}




sub BUILD {
	my $self = shift;
	$self->initialize_rc;
}





has 'rc'             => (is=>'ro',isa=>'Str',default=>"$ENV{HOME}/.org-asana-rc"); # rcfile in YAML format contains our API key, etc.
has 'dir'            => (is=>'rw',isa=>'Str',default=>"$ENV{HOME}/org-asana");
has 'api_key'        => (is=>'rw',isa=>'Str');

sub initialize_rc {
	my $self = shift;
	if (-e $self->rc) {
		my $rc_config = LoadFile($self->rc);
		for my $config (qw(dir api_key)) { $self->$config($rc_config->{$config}) if $rc_config->{$config}; }
	}
	elsif (-t STDOUT) {
		print "*** .org-asana-rc file not found. Creating.\n";
		print "  - Work dir will default to ~/org-asana/\n";
		print "  - Need Asana API key.\n";
		print "  - Please enter your Asana API key, available at https://app.asana.com/-/account_api\n";
		chomp(my $api_key = <STDIN>);
		if (length($api_key) ne 32) { die "An Asana API key should be 32 characters long.\n"; }
		DumpFile($self->rc, { api_key => $api_key });
		$self->api_key($api_key);
	}
	$self->test_api_key;
}

sub test_api_key {
	my $self = shift;
	my $me;
	eval {
		my $asana = WWW::Asana->new( api_key => $self->api_key );
		$me = $asana->me;
	};
	if ($@ or not $me or not $me->email) {
		die ("Couldn't initialize WWW::Asana. Is your API key correct? (" . $self->api_key .")\n");
	}
	$self->verbose("  - WWW::Asana works. You are %s (%s)", $me->email, $me->name);
}





has 'sleep_interval' => (is=>'rw',isa=>'Num',default=>10);
has 'sleep_times'    => (is=>'rw',isa=>'Num',default=>0);

sub sleep {
	my $self = shift;
	$self->verbose("  - sleeping. (%s)", scalar localtime);
	sleep $self->sleep_interval if $self->sleep_times;
	$self->sleep_times($self->sleep_times+1);
}




use Org::Asana::Cache::Org;
use Org::Asana::Cache::Asana;

sub manage_caches {
	my $self = shift;
	$self->load_cache_asana;
	$self->load_cache_org;
}

has 'cache_asana' => (is=>'rw', isa=>'Org::Asana::Cache::Asana', predicate=>'has_cache_asana', clearer=>'clear_cache_asana');

sub load_cache_asana {
	my $self = shift;
	my $cache_asana = Org::Asana::Cache::Asana->new(oa=>$self);
	if (not $cache_asana->is_loaded
		or
		$cache_asana->is_expired) {
		$self->clear_cache_asana;
		$cache_asana->build;
	}
}

has 'cache_org' => (is=>'rw', isa=>'Org::Asana::Cache::Org', predicate=>'has_cache_org', clearer=>'clear_cache_org');

sub load_cache_org {
	my $self = shift;
	my $cache_org = Org::Asana::Cache::Org->new(oa=>$self);
	if (not $cache_org->is_loaded
		or
		$cache_org->is_expired) {
		$self->clear_cache_org;
		$cache_org->build;
	}
}

1;

