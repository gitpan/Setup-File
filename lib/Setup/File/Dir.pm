package Setup::File::Dir;

use Setup::File;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_dir);

our $VERSION = '0.19'; # VERSION

# now moved to Setup::File

sub setup_dir {
    [501, "Moved to Setup::File"];
}

1;
# ABSTRACT: Setup directory (existence, mode, permission)

__END__

=pod

=encoding UTF-8

=head1 NAME

Setup::File::Dir - Setup directory (existence, mode, permission)

=head1 VERSION

This document describes version 0.19 of Setup::File::Dir (from Perl distribution Setup-File), released on 2014-05-02.

=for Pod::Coverage ^(setup_dir)$

=head1

Moved to

=head1 SEE ALSO

L<Setup>

L<Setup::File>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Setup-File>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-Setup-File>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Setup-File>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
