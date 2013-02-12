package Org::Asana;

# https://github.com/mengwong/org-asana/

use Moose;
use WWW::Asana;
use YAML qw(LoadFile DumpFile);
use Carp;
use File::Path;

has 'verbosity'        => (is=>'rw',isa=>'Num|Str',default=>0);
has 'verbosity_prefix' => (is=>'rw',isa=>'Str',default=>"");
has 'sensitive'        => (is=>'rw',isa=>'Bool',default=>0); # do we die on error? helps with debugging.

sub verbose {
	my $self = shift;
	return if not $self->verbosity;
	print  STDERR $self->verbosity_prefix;
	printf STDERR @_;
	print  STDERR "\n";
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

has 'asana_me' => (is=>'rw', isa=>'WWW::Asana::User');
has 'asana_www' => (is=>'rw', isa=>'WWW::Asana');

sub test_api_key {
	my $self = shift;
	my $asana;
	my $me;
	eval {
		$asana = WWW::Asana->new( api_key => $self->api_key, singleton_instance=>1 );
		$me = $asana->me;
	};
	if ($@ or not $me or not $me->email) {
		die ("Couldn't initialize WWW::Asana. Is your API key correct? (" . $self->api_key .")\n$@\n");
	}
	$self->verbose("  - WWW::Asana works. You are %s (%s)", $me->email, $me->name);
	$self->asana_me($me);
	$self->asana_www($asana);
}





has 'sleep_interval' => (is=>'rw',isa=>'Num',default=>30);
has 'sleep_times'    => (is=>'rw',isa=>'Num',default=>0);

sub sleep {
	my $self = shift;
	$self->verbose("  - sleeping. (%s)", scalar localtime);
	sleep $self->sleep_interval if $self->sleep_times;
	$self->sleep_times($self->sleep_times+1);
}




use Org::Asana::Cache::Org;
use Org::Asana::Cache::Asana;
use Org::Asana::Cache::Merge;

sub manage_caches {
	my $self = shift;
	$self->verbose("managing caches.");
	$self->clear_cache_asana; $self->cache_asana->rebuild_as_needed;
	$self->clear_cache_org;   $self->cache_org->rebuild_as_needed;
	$self->clear_cache_merge; $self->cache_merge if ($self->cache_asana->is_usable and $self->cache_org->is_usable);
}

has 'cache_asana' => (is=>'rw', isa=>'Org::Asana::Cache::Asana', lazy_build=>1);
sub _build_cache_asana { Org::Asana::Cache::Asana->new(oa=>shift) }

has 'cache_org' => (is=>'rw', isa=>'Org::Asana::Cache::Org', lazy_build=>1);
sub _build_cache_org { Org::Asana::Cache::Org->new(oa=>shift) }

has 'cache_merge' => (is=>'rw', isa=>'Org::Asana::Cache::Merge', lazy_build=>1);
sub _build_cache_merge { Org::Asana::Cache::Merge->new(oa=>shift) }
# workspace -> project -> task -> story
# workspace -> project -> story
# workspace -> tag


sub sync {
	my $self = shift;
	return if not $self->has_cache_merge;
	$self->cache_merge->calculate_changes;
	$self->merge_to_asana;
	$self->merge_to_org;
}


sub merge_to_asana {
	my $self = shift;
	$self->verbose("merging to asana");

}

sub merge_to_org {
	my $self = shift;
	$self->verbose("merging to org");

	# organize by workspace (directory)
	# then by user          (file)
	# then by project       (org)
	# then by task          (org)
	# then by story         (org)

	my $output_buffers = {};

	# return if $self->org_file_is_being_edited;

	# XXX: this is where i left off for the night. use a2o to output to org.

	$self->cache_merge->walk(sub {
		my ($self, $obj, $path) = (shift, shift, shift);
		$self->oa->verbose("merge_to_org: %s %s %s", ref($obj), $obj->id, $obj->can("name") ? $obj->name : $obj->can("text") ? $obj->text : "NO-NAME");
						 }
		);
#				my %properties;
#				$properties{asana_ASSIGNEE}        = $task->assignee->id if $task->assignee;
#				$properties{asana_ASSIGNEE_STATUS} = $task->assignee_status;
#				$properties{asana_CREATED_AT}      = $task->created_at."" if $task->has_created_at;
#				$properties{asana_COMPLETED}       = $task->completed . "";
#				$properties{asana_COMPLETED_AT}    = $task->completed_at."" if $task->has_completed_at;
#				$properties{asana_DUE_ON}          = $task->due_on_value if $task->has_due_on;
#				$properties{asana_FOLLOWERS}       = join " ", map { $_->id } @{ $task->followers } if @{ $task->followers };
#				$properties{asana_MODIFIED_AT}     = $task->modified_at."" if $task->has_modified_at;
#				$properties{asana_PROJECTS}        = join " ", map { $_->id } @{ $task->projects  } if @{ $task->projects };
#				$properties{asana_PARENT}          = $task->parent->id if $task->parent and $task->parent->id;
#				$contents{workspaces}{$workspace->id}->{tasks}{$task->id}->{properties} = \%properties;

}

1;

