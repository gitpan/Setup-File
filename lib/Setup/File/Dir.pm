package Setup::File::Dir;

use Setup::File;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_dir);

our $VERSION = '0.17'; # VERSION

# now moved to Setup::File

sub setup_dir {
    [501, "Moved to Setup::File"];
}

1;
# ABSTRACT: Setup directory (existence, mode, permission)


__END__
=pod

=head1 NAME

Setup::File::Dir - Setup directory (existence, mode, permission)

=head1 VERSION

version 0.17

=head1

Moved to

=head1 SEE ALSO

L<Setup>

L<Setup::File>

=head1 DESCRIPTION


This module has L<Rinci> metadata.

=head1 FUNCTIONS


None are exported by default, but they are exportable.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

