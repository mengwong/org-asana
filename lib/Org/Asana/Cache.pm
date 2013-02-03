package Org::Asana::Cache;


# a Cache object has ->contents
# the contents are a Perl version of both the Org and the Asana data structures.
# the Perl version serves as a translation layer importable and exportable to both Org and Asana.

use Moose::Role;
use YAML qw(LoadFile DumpFile);

requires 'build_cache';

has oa => (is=>'ro', isa=>'Org::Asana', required=>1);

has is_loaded => (is=>'rw', isa=>'Bool', default=>0);

has scan_time => (is=>'rw', isa=>'Num');
has scan_start_time => (is=>'rw', isa=>'Num');

requires 'expires_after';
sub is_expired {
	my $self = shift;
	if (my $is_expired = ($self->scan_time + $self->expires_after < time)) {
		$self->oa->verbose("*** %s is expired (%d+%d < %d; scan_time=%s)", ref($self), $self->scan_time, $self->expires_after, time, scalar(localtime($self->scan_time)));
		return 1;
	}
	return 0;
}

sub previous_is_running {
	my $self = shift;f

	my $pid = $self->runpidfile_read;

	if ($pid and kill(0,$pid)) {
		$self->oa->verbose("!!! previous cache build is running -- %s contains PID %s", $self->runpidfilename, $pid);
		return 1;
	}
	return 0;
}

sub runpidfile_read {
	my $self = shift;
	return if not -e $self->runpidfilename;
	open FILE, $self->runpidfilename;
	my $pid = <FILE>; chomp $pid;
	close FILE;
	return $pid;
}

sub runpidfile_write {
	my $self = shift;
	open FILE, ">", $self->runpidfilename;
	print FILE $$,"\n";
	close FILE;
}

sub runpidfile_clear {
	my $self = shift;
	unlink ($self->runpidfilename);
}

sub build { # not BUILD. build() actually builds the cache.
	my $self = shift;
	# go launch the build process

	if ($self->previous_is_running) {
		$self->oa->verbose("*** not launching build of (%s) because previous is still running.", ref($self));
		return;
	}
	else { # maybe an earlier build completed?
		$self->oa->verbose("*** launching build of %s", ref($self));
	}		

	if    (fork()) {                          wait; }
	elsif (fork()) {                          exit; }
	else           { $self->runpidfile_write;
					 $self->scan_start_time(time);
					 $self->build_cache;
					 $self->scan_time($self->scan_start_time);
					 $self->save_contents_tofile;
					 $self->runpidfile_clear; exit; }
}

requires 'cachefilename';

has contents => (is=>'rw', isa=>'HashRef');

# contents contains:
# - contents: { }
# - scan_time: time()
# - part_or_full: part|full (optional)

sub BUILD {
	my $self = shift;
	$self->reload_fromfile;
}	

sub reload_fromfile {
	my $self = shift;

	if (not -e $self->cachefilename) { $self->is_loaded(0); return; }

	my $cache;
	eval { $cache = LoadFile($self->cachefilename); }; if ($@) { die "!!! error $@ while loading " . $self->cachefilename; }

	if (not defined $cache->{contents}) { $self->oa->verbose("*** loaded %s cache, but it's empty.", ref($self)); return; }
	$self->oa->verbose("*** successfully reloaded cache for %s", ref($self));
	$self->is_loaded(1);
	$self->contents($cache->{contents});
	$self->scan_time($cache->{scan_time});
}

sub save_contents_tofile {
	my $self = shift;
	use File::Temp qw(tempfile);
	my ($fh, $filename) = tempfile();
	$self->oa->verbose("**** dumping %s to %s via tempfile %s", ref($self), $self->cachefilename, $filename);
	DumpFile($filename, { contents => $self->contents,
						  scan_time => $self->scan_time,
			 });
	rename($filename, $self->cachefilename); # atomic rename.
}

1;
