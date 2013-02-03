package Org::Asana::Cache::Asana;

use Moose;

has runpidfilename => (is=>'ro',isa=>'Str',default=>"/tmp/build-cache-asana.pid");
has cachefilename => (is=>'rw', isa=>'Str', lazy=>1, default=>sub{shift->oa->dir . "/cache/asana.yaml"});
has expires_after => (is=>'rw', isa=>'Num',default=>7200);

with 'Org::Asana::Cache';

sub build_cache {
	my $self = shift;
	$self->oa->verbose("**** Building Asana Cache...");
	sleep 60;
	$self->oa->verbose("**** Asana Cache Build Complete.");
}

has cachefilename => (is=>'rw', isa=>'Str', lazy=>1, default=>sub{shift->oa->dir . "/cache/asana.yaml"});

1;
