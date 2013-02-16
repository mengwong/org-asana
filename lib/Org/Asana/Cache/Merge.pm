package Org::Asana::Cache::Merge;

use Moose;

has cachefilename => (is=>'rw', isa=>'Str', lazy=>1, default=>sub{shift->oa->dir . "/cache/merge.yaml"});

with 'Org::Asana::Cache';

use feature qw(say);
use Tie::IxHash;

sub BUILD {
	my $self = shift;
	$self->build_cache;
}

sub build_cache {
	my $self = shift;

	my %contents; tie(%contents, "Tie::IxHash"); $self->contents(\%contents);
	$self->merge_from_asana;
	$self->merge_from_org;

}

sub merge_from_asana {
	my $self = shift;

	my $objcount = 0;
	$self->oa->cache_asana->walk( sub {
		my ($ca, $obj, $path) = (shift, shift, shift);
		$self->oa->verbose("merge_from_asana: %s %s %s",
							join ("/",@$path), ref($obj), $obj->can("name") ? $obj->name : $obj->can("text") ? $obj->text : "NO-NAME");

		$self->contents->{join"/",@$path}->{asana} = $obj;
								  });
}

sub merge_from_org {
	my $self = shift;

	$self->oa->cache_org->walk( sub {
		my ($ca, $obj, $path) = (shift, shift, shift);
		$self->oa->verbose("merge_from_org: %s %s %s",
						   join ("/",@$path),
						   ref($obj), $obj->can("name") ? $obj->name : $obj->can("text") ? $obj->text : "NO-NAME");

		$self->contents->{join"/",@$path}->{org} = $obj;
								  });
}

sub calculate_changes {
	my $self = shift;
	$self->oa->verbose("calculating changes");
	foreach my $path (keys %{$self->contents}) {
		my $obj_asana = $self->contents->{$path}->{asana};
		my $obj_org   = $self->contents->{$path}->{org};

		if    ($obj_asana and not $obj_org)   {

			$self->oa->verbose("change: %s asana exists; org doesn't exist. %s",			$path, ($obj_asana->can("name") ? $obj_asana->name : "NO-NAME"));
			$self->contents->{$path}->{resolution} = "create in org";
		}

		elsif ($obj_org   and not $obj_asana) {

			$self->oa->verbose("change: %s org exists; asana doesn't exist. %s",			$path, ($obj_org->can("name")   ? $obj_org->name   : "NO-NAME"));

			if ($obj_org->can("confirm_create_asana") and
				$obj_org->confirm_create_asana
				) {
				$self->contents->{$path}->{resolution} = "create in asana";
				
			} else {
				$self->contents->{$path}->{resolution} = "request confirmation in org";
			}
		}

		elsif (not $obj_asana->can("modified_at") or not $obj_org->can("modified_at")) { 

			$self->oa->verbose("change: %s no modtime to compare. %s",                      $path, ($obj_asana->can("name") ? $obj_asana->name : "NO-NAME"));
			$self->contents->{$path}->{resolution} = "noop";
		}

		# XXX: detect conflicts.

		elsif (($obj_asana->modified_at||$obj_asana->created_at) >  ($obj_org->modified_at||$obj_org->created_at)) {

			$self->oa->verbose("change: %s asana is newer. %s", 							$path, ($obj_asana->can("name") ? $obj_asana->name : "NO-NAME"));
			$self->contents->{$path}->{resolution} = "update org";
		}

		elsif (($obj_asana->modified_at||$obj_asana->created_at) <  ($obj_org->modified_at||$obj_org->created_at)) {

			$self->oa->verbose("change: %s org is newer. %s",								$path, ($obj_org  ->can("name") ? $obj_org  ->name : "NO-NAME"));
			$self->contents->{$path}->{resolution} = "update asana";
		}

		elsif (($obj_asana->modified_at||$obj_asana->created_at) == ($obj_org->modified_at||$obj_org->created_at)) {

			$self->oa->verbose("change: %s no change. %s",									$path, ($obj_asana->can("name") ? $obj_asana->name : "NO-NAME"));
			$self->contents->{$path}->{resolution} = "noop";

		}
		else { $self->oa->verbose("change: ERROR -- how did we get here?") }
	}
}

1;
