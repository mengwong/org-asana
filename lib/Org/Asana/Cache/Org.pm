package Org::Asana::Cache::Org;

use Moose;

has runpidfilename => (is=>'ro',isa=>'Str',default=>"/tmp/build-cache-org.pid");
has cachefilename => (is=>'rw', isa=>'Str', lazy=>1, default=>sub{shift->oa->dir . "/cache/org.yaml"});

has expires_after => (is=>'rw', isa=>'Num',default=>600);

with 'Org::Asana::Cache';




use Org::Parser;

sub orgfiles {
	my $self = shift;

	opendir (WORKSPACES, $self->oa->dir."/workspaces");
	my @workspaces = grep { $_ ne "." and $_ ne ".." and -d $self->oa->dir."/workspaces/$_" } readdir(WORKSPACES);
	closedir WORKSPACES;

	my @orgfiles;
	foreach my $workspace (map { $self->oa->dir . "/workspaces/$_" } @workspaces) {
		$self->oa->verbose("**** looking at %s", $workspace);
		opendir WORKSPACE, $workspace;
		my @user_files = grep { -f and /\.org$/ } map { "$workspace/$_" } readdir(WORKSPACE);
		close WORKSPACE;
		push @orgfiles, @user_files;
	}
	return @orgfiles;
}

sub is_expired {
	my $self = shift;
	# let's just take a look at the files, shall we?

	# if any of the orgfiles on disk have a modification time later than the scan_time, we are in an expired condition.
	
	return 0;
}

sub build_cache {
	my $self = shift;
	$self->oa->verbose("**** Building Org Cache...");

	my $contents = {};

	# all of these are the relevant IDs
	my $_user;
	my $_workspace;
	my $_project = "ORPHAN";
	my $_section;
	my $_task;
	my $_subtask;
	my $_story;

	my $objcount=0;

	foreach my $orgfile ($self->orgfiles) {
		$self->oa->verbose("**** parsing org file %s", $orgfile);

		my $orgp = Org::Parser->new();
		my $doc = $orgp->parse_file($orgfile);

		$_user      = $doc->properties->{"asana_user_id"};

		$doc->walk(sub {
			my ($el) = @_;
			return unless $el->isa('Org::Element::Headline');
			return unless $el->tags and grep { ($_ eq "workspace" or
												$_ eq "project" or
												$_ eq "section" or
												$_ eq "task" or
												$_ eq "subtask" or
												$_ eq "feed") } @{$el->tags};

			$objcount++;

			$_workspace = $el->get_property("asana_ID") if (grep { $_ eq "workspace" } @{$el->tags});
			$_project   = $el->get_property("asana_ID") if (grep { $_ eq "project"   } @{$el->tags});
			$_section   = $el->get_property("asana_ID") if (grep { $_ eq "section"   } @{$el->tags});
			$_task      = $el->get_property("asana_ID") if (grep { $_ eq "task"      } @{$el->tags});
			$_subtask   = $el->get_property("asana_ID") if (grep { $_ eq "subtask"   } @{$el->tags});
			$_story     = $el->get_property("asana_ID") if (grep { $_ eq "feed"      } @{$el->tags});

			if (grep {$_ eq "workspace"} @{$el->tags}) {
				$contents->{workspaces}{$_workspace}->{name} = $el->title->as_string;
			}
			if (grep {$_ eq "project"} @{$el->tags}) {
				$contents->{workspaces}{$_workspace}->{projects}{$_project}->{name} = $el->title->as_string;
			}
			if (grep {$_ eq "section"} @{$el->tags}) { # XXX: either give sections their own category level, or treat them as tasks.
				$contents->{workspaces}{$_workspace}->{projects}{$_section}->{name} = $el->title->as_string;
			}
			if (grep {$_ eq "task"} @{$el->tags}) {
				$contents->{workspaces}{$_workspace}->{projects}{$_section}->{tasks}{$_task}->{name} = $el->title->as_string;
				$contents->{workspaces}{$_workspace}->{projects}{$_section}->{tasks}{$_task}->{properties} = $el->get_drawer("PROPERTIES")->properties;
				$contents->{workspaces}{$_workspace}->{projects}{$_section}->{tasks}{$_task}->{note} = $el->children_as_string;
			}

				   });
	}

	$self->oa->verbose("**** Org Cache Build complete. Read %d objects", $objcount);
	$self->contents($contents);
}

1;
