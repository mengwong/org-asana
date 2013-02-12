package Org::Asana::HasProperties;
use Moose::Role;
has properties => (is=>'rw', isa=>'HASHREF', default=>sub{{}});
1;
