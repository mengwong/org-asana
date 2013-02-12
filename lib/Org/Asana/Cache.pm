package Org::Asana::Cache;


# a Cache object has ->contents
# the contents are a Perl version of both the Org and the Asana data structures.
# the Perl version serves as a translation layer importable and exportable to both Org and Asana.

use Moose::Role;
use YAML qw(LoadFile DumpFile);
use Tie::IxHash;
use Class::Load ':all';

requires 'build_cache';

has oa => (is=>'ro', isa=>'Org::Asana', required=>1);

has is_loaded => (is=>'rw', isa=>'Bool', default=>0);
has is_usable => (is=>'rw', isa=>'Bool', default=>0);

has scan_time => (is=>'rw', isa=>'Num', default=>0);
has scan_start_time => (is=>'rw', isa=>'Num');

sub previous_is_running {
	my $self = shift;

	my $pid = $self->runpidfile_read;

	if ($pid and kill(0,$pid)) {
		$self->oa->verbose("!!! previous cache build is running -- %s contains PID %s", $self->runpidfilename, $pid);
		return 1;
	} elsif ($pid) {
		$self->oa->verbose("!!! previous cache build $pid seems to have died. If that's okay, rm %s", $self->runpidfilename);
		die if $self->oa->sensitive;
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
	$self->oa->verbose("launched");
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
		$self->oa->verbose("*** forking build of %s", ref($self));
	}		

	if    (fork()) {                          wait; }
	elsif (fork()) {                          exit; }
	else           { $self->oa->verbosity_prefix(sprintf "-child- %s %s: ", ref($self), $$);
					 $self->runpidfile_write;
					 $self->scan_start_time(time);
					 $self->build_cache;
					 $self->scan_time($self->scan_start_time);
					 $self->save_contents_tofile;
					 $self->runpidfile_clear;
					 $self->oa->verbose("build complete. exiting. build took %d seconds.", time - $self->scan_start_time);
					 exit; }
}

requires 'cachefilename';

has contents => (is=>'rw', isa=>'HashRef');

# contents contains:
# - contents: { }
# - scan_time: time()
# - part_or_full: part|full (optional)

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




sub walk_contents {
	my $self = shift;
	my $callback = shift;
	my $contents = shift;
	my $path = shift;

#	$self->oa->verbose("walk_contents - @{$path}");
#	$self->oa->verbose("              - $_ = $contents->{$_}") for keys %$contents;

	while (my ($type, $subtree) = each %$contents) {
		if ($type eq "obj") { my $obj = $subtree;
							  if (ref($obj) =~ /::/) { load_class(ref($obj)) unless is_class_loaded(ref($obj)); }
							  $callback->($self, $obj, $path, $contents);
#							  $self->oa->verbose("walk_contents >> @{$path} >> callbacking object $obj");
		} else {
			foreach my $id (keys %$subtree) {
				my $subsub = $subtree->{$id};
#				$self->oa->verbose("walk_contents >> @{[%$path]} >> recursing into $type $id");
				next if not $subsub;
				$self->walk_contents($callback, $subsub, [ @$path, $type => $id ] );
			}
		}
	}
}


sub walk {
	my $self = shift;
	my $callback = shift;
	$self->walk_contents($callback, $self->contents, [] );
}

1;
