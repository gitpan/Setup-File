package Setup::File;
BEGIN {
  $Setup::File::VERSION = '0.04';
}
# ABSTRACT: Ensure file (non-)existence, mode/permission, and content

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Digest::MD5 qw(md5_hex);
use File::chmod;
use File::Copy::Recursive qw(rmove);
use File::Path qw(remove_tree);
use File::Slurp;
use File::Temp qw(tempfile tempdir);
use UUID::Random;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_file);

our %SPEC;

$SPEC{setup_file} = {
    summary  => "Ensure file (non-)existence, mode/permission, and content",
    description => <<'_',
On do, will create file (if it doesn't already exist) and correct
mode/permission as well as content.

On undo, will restore old mode/permission/content, or delete the file again if
it was created by this function *and* its content hasn't changed since.

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

_
    args     => {
        path => ['str*' => {
            summary => 'Path to file',
            description => <<'_',

File path needs to be absolute so it's normalized.

_
            arg_pos => 1,
            match   => qr!^/!,
        }],
        should_exist => ['bool' => {
            summary => 'Whether file should exist',
            description => <<'_',

If undef, file need not exist. If set to 0, file must not exist and will be
deleted if it does. If set to 1, file must exist and will be created if it
doesn't.

_
        }],
        mode => ['str' => {
            summary => 'Expected permission mode',
        }],
        owner => ['str' => {
            summary => 'Expected owner',
        }],
        group => ['str' => {
            summary => 'Expected group',
        }],
        check_content_code => ['code' => {
            summary => 'Code to check content',
            description => <<'_',

If unset, file will not be checked for its content. If set, code will be called
whenever file content needs to be checked. Code will be passed the file content
and should return a boolean value indicating whether content is acceptable.

_
        }],
        gen_content_code => ['code' => {
            summary => 'Code to generate content',
            description => <<'_',

If set, whenever a new file content is needed (e.g. when file is created or file
content reset), this code will be called to provide it. If unset, empty string
will be used instead.

Code will be passed the current content (or undef) and should return the new
content.

_
        }],
        allow_symlink => ['bool*' => {
            summary => 'Whether symlink is allowed',
            description => <<'_',

If existing file is a symlink then if allow_symlink is false then it is an
unacceptable condition (the symlink will be replaced if replace_symlink is
true).

Note: if you want to setup symlink instead, use Setup::Symlink.

_
            default => 0,
        }],
        replace_symlink => ['bool*' => {
            summary => "Replace existing symlink if it needs to be replaced",
            default => 1,
        }],
        replace_file => ['bool*' => {
            summary => "Replace existing file if it needs to be replaced",
            default => 1,
        }],
        replace_dir => ['bool*' => {
            summary => "Replace existing dir if it needs to be replaced",
            default => 1,
        }],
    },
    features => {undo=>1, dry_run=>1},
};
sub setup_file { _setup_file_or_dir('file', @_) }

# return 1 if dir exists and empty
sub _dir_is_empty {
    my ($dir) = @_;
    return unless (-d $dir);
    return unless opendir my($dh), $dir;
    my @d = grep {$_ ne '.' && $_ ne '..'} readdir($dh);
    my $res = !@d;
    #$log->tracef("dir_is_empty(%s)? %d", $dir, $res);
    $res;
}

sub _setup_file_or_dir {
    my ($which, %args) = @_;
    die "BUG: which should be file/dir"
        unless $which eq 'file' || $which eq 'dir';

    my $dry_run        = $args{-dry_run};
    my $undo_action    = $args{-undo_action} // "";

    # check args
    my $path           = $args{path};
    $path              =~ m!^/!
        or return [400, "Please specify an absolute path"];
    my $should_exist   = $args{should_exist};
    my $allow_symlink  = $args{allow_symlink} // 1;
    my $replace_file   = $args{replace_file} // 1;
    my $replace_dir    = $args{replace_dir} // 1;
    my $replace_sym    = $args{replace_symlink} // 1;
    my $owner          = $args{owner};
    my $group          = $args{group};
    my $mode           = $args{mode};
    my $check_ct       = $args{check_content_code};
    my $gen_ct         = $args{gen_content_code};
    return [400, "If check_content_code is specified, ".
                "gen_content_code must also be specified"]
        if defined($check_ct) && !defined($gen_ct);
    my $cur_content;

    # check current state and collect steps
    my $is_symlink     = (-l $path);
    my $exists         = (-e _);
    # -l does lstat, we need stat
    #my @st = stat($is_symlink ? $path : _);
    my @st             = stat($path); # stricture complains about _
    return [500, "Can't stat (1): $!"] if $exists && !$is_symlink && !@st;
    my $is_file        = (-f _);
    my $is_dir         = (-d _);

    # exists means whether *target* exists, if symlink is allowed. while
    # symlink_exists means the symlink itself exists.
    my $symlink_exists;
    if ($allow_symlink && $is_symlink) {
        $symlink_exists = $exists;
        $exists = (-e _) if $symlink_exists;
    }

    my $steps;
    if ($undo_action eq 'undo') {
        $steps = $args{-undo_data} or return [400, "Please supply -undo_data"];
    } elsif ($undo_action eq 'redo') {
        $steps = $args{-redo_data} or return [400, "Please supply -redo_data"];
    } else {
        $steps = [];
        {
            if (defined($should_exist) && !$should_exist && $exists) {
                $log->trace("nok: $which should not exist but does");
                push @$steps, [$is_dir ? "rm_r" : "rmfile"];
                last;
            }
            if ($should_exist && !$exists) {
                $log->trace("nok: $which should exist but doesn't");
                push @$steps, ["rmsym"] if $symlink_exists;
                push @$steps, ["create"];
                last;
            }
            if (!$allow_symlink && $is_symlink) {
                $log->trace("nok: $which should not be symlink but is");
                if (!$replace_sym) {
                    return [412, "must replace symlink but instructed not to"];
                }
                push @$steps, ["rmsym"], ["create"];
                last;
            }
            last unless $exists;
            if ($is_dir && $which eq 'file') {
                $log->trace("nok: file expected but is dir");
                if (!$replace_dir) {
                    return [412, "must replace dir but instructed not to"];
                }
                push @$steps, ["rm_r"], ["create"];
                last;
            } elsif (!$is_dir && $which eq 'dir') {
                $log->trace("nok: dir expected but is file");
                if (!$replace_file) {
                    return [412, "must replace file but instructed not to"];
                }
                push @$steps, ["rm_r"], ["create"];
                last;
            }
            if (defined $mode) {
                my $cur_mode = $st[2] & 07777;
                $mode = getchmod($mode, $cur_mode)
                    if $mode =~ /[+=-]/; # symbolic mode
                if ($mode != $cur_mode) {
                    $log->tracef("nok: $which mode is %04o, ".
                                     "but it should be %04o",
                                 $cur_mode, $mode);
                    push @$steps, ["chmod", $mode];
                }
            }
            if (defined $owner) {
                my $cur_owner = $st[4];
                my @pw;
                if ($owner !~ /^\d+$/) {
                    @pw = getpwnam($owner);
                    $owner = $pw[2];
                } else {
                    @pw = getpwuid($owner);
                }
                if ($owner != $cur_owner) {
                    my @pwc = getpwuid($cur_owner);
                    $log->tracef("nok: $which owner is %s but it should be %s",
                                 @pwc ? $pwc[0] : $cur_owner,
                                 @pw ? $pw[0] : $owner);
                    push @$steps, ["chown", $owner];
                }
            }
            if (defined $group) {
                my $cur_group = $st[5];
                my @gr;
                if ($group !~ /^\d+$/) {
                    @gr = getgrnam($group);
                    $group = $gr[2];
                } else {
                    @gr = getgrgid($group);
                }
                if ($group != $cur_group) {
                    my @grc = getgrgid($cur_group);
                    $log->tracef("nok: $which group is %s but it should be %s",
                                 @grc ? $grc[0] : $cur_group,
                                 @gr ? $gr[0] : $group);
                    push @$steps, ["chown", undef, $owner];
                }
            }
            if (defined $check_ct) {
                $cur_content = read_file($path, err_mode=>'quiet');
                return [500, "Can't read file content: $!"]
                    unless defined($cur_content);
                my $res = $check_ct->(\$cur_content);
                unless ($res) {
                    $log->tracef("nok: file content fails check_content_code");
                    push @$steps, ["set_content", \($gen_ct->(\$cur_content))];
                }
            }
        }
    }

    return [400, "Invalid steps, must be an array"]
        unless $steps && ref($steps) eq 'ARRAY';
    return [200, "Dry run"] if $dry_run && @$steps;

    # create tmp dir for undo
    my $save_undo    = $undo_action ? 1:0;
    my $undo_hint = $args{-undo_hint} // {};
    return [400, "Invalid -undo_hint, please supply a hashref"]
        unless ref($undo_hint) eq 'HASH';
    my $tmp_dir = $undo_hint->{tmp_dir} // "$ENV{HOME}/.setup";
    if ($save_undo && !(-d $tmp_dir) && !$dry_run) {
        mkdir $tmp_dir or return [500, "Can't make temp dir `$tmp_dir`: $!"];
    }
    my $save_path = "$tmp_dir/".UUID::Random::generate;

    # perform the steps
    my $rollback;
    my $undo_steps = [];
  STEPS:
    for my $i (0..@$steps-1) {
        my $step = $steps->[$i];
        next unless defined $step; # can happen even when steps=[], due to redo
        $log->tracef("step %d of 0..%d: %s", $i, @$steps-1, $step);
        my $err;
        return [400, "Invalid step (not array)"] unless ref($step) eq 'ARRAY';
        if ($step->[0] eq 'rmsym') {
            if ((-l $path) || (-e _)) {
                my $t = readlink($path) // "";
                if (unlink $path) {
                    unshift @$undo_steps, ["ln", $t];
                } else {
                    $err = "Can't remove $path: $!";
                }
            }
        } elsif ($step->[0] eq 'ln') {
            my $t = $step->[1];
            unless ((-l $path) && readlink($path) eq $t) {
                if (symlink $t, $path) {
                    unshift @$undo_steps, ["rmsym"];
                } else {
                    $err = "Can't symlink $path -> $t: $!";
                }
            }
        } elsif ($step->[0] eq 'rm_r') {
            if ((-l $path) || (-e _)) {
                # do not bother to save file/dir if not asked
                if ($save_undo) {
                    if (rmove $path, $save_path) {
                        unshift @$undo_steps, ["restore", $save_path];
                    } else {
                        $err = "Can't move file/dir $path -> $save_path: $!";
                    }
                } else {
                    remove_tree($path, {error=>\my $e});
                    if (@$e) {
                        $err = "Can't remove file/dir $path: ".dumpp($e);
                    }
                }
            }
        } elsif ($step->[0] eq 'rmfile') {
            # will only delete if content is unchanged from time of create,
            # content is represented by hash
            if ((-l $path) || (-e _)) {
                my $ct = read_file($path, err_mode=>'quiet');
                if (!defined($ct)) {
                    $err = "Can't read file: $!";
                } else {
                    my $ct_hash = md5_hex($ct);
                    if ($ct_hash ne $step->[1]) {
                        $log->warn("File content has changed, not removing");
                    } else {
                        if (unlink $path) {
                            unshift @$undo_steps, ["create", \$ct];
                        } else {
                            $err = "Can't unlink $path: $!";
                        }
                    }
                }
            }
        } elsif ($step->[0] eq 'rmdir') {
            if ((-l $path) || (-e _)) {
                if (rmdir $path) {
                    unshift @$undo_steps, ["create"];
                } else {
                    $err = "Can't rmdir $path: $!";
                }
            }
        } elsif ($step->[0] eq 'restore') {
            if ((-l $path) || (-e _)) {
                $err = "Can't restore $step->[1] -> $path: already exists";
            } elsif (rmove $step->[1], $path) {
                unshift @$undo_steps, ["rm_r"];
            } else {
                $err = "Can't restore $step->[1] -> $path: $!";
            }
        } elsif ($step->[0] eq 'create') {
            if ((-l $path) || (-e _)) {
                $err = "Can't create $path: already exists";
            } else {
                {
                    if ($which eq 'dir') {
                        mkdir $path
                            or do { $err = "Can't mkdir: $!"; last };
                        chown $owner//-1, $group//-1, $path
                            or do { $err = "Can't chown: $!"; last };
                        defined($mode) and chmod $mode, $path ||
                            do { $err = "Can't chmod: $!"; last };
                        unshift @$undo_steps, ["rmdir"];
                    } else {
                        my $ct;
                        if (defined $step->[1]) {
                            $ct = $step->[1];
                        } else {
                            $ct = $gen_ct ? $gen_ct->(\$cur_content) : "";
                        }
                        my $ct_hash = md5_hex($ct);
                        write_file($path, {err_mode=>'quiet', atomic=>1}, $ct)
                            or do { $err = "Can't write file: $!"; last };
                        chown $owner//-1, $group//-1, $path
                            or do { $err = "Can't chown: $!"; last };
                        defined($mode) and chmod $mode, $path ||
                            do { $err = "Can't chmod: $!"; last };
                        unshift @$undo_steps, ["rmfile", $ct_hash];
                    }
                }
            }
        } elsif ($step->[0] eq 'set_content') {
            {
                my $cur_content = read_file($path, err_mode=>'quiet');
                defined($cur_content)
                    or do { $err = "Can't read file: $!"; last };
                write_file($path, {err_mode=>'quiet', atomic=>1}, ${$step->[1]})
                    or do { $err = "Can't write file: $!"; last };
                unshift @$undo_steps, ["set_content", \$cur_content];
                # need to chown + chmod temporary file again
                chown $owner//-1, $group//-1, $path
                    or do { $log->warn("Can't chown: $!") };
                defined($mode) and chmod $mode, $path ||
                    do { $log->warn("Can't chmod: $!") };
            }
        } elsif ($step->[0] eq 'chmod') {
            my @st = lstat($path);
            if (!@st) {
                $log->warn("Can't stat, skipping chmod");
            } else {
                if (chmod $step->[1], $path) {
                    unshift @$undo_steps, ["chmod", $st[2] & 07777];
                } else {
                    $err = $!;
                }
            }
        } elsif ($step->[0] eq 'chown') {
            my @st = lstat($path);
            if (!@st) {
                $log->warn("Can't stat, skipping chmod");
            } else {
                if (chown $step->[1]//-1, $step->[2]//-1, $path) {
                    unshift @$undo_steps,
                        ["chown",
                         defined($step->[1]) ? $st[4] : undef,
                         defined($step->[2]) ? $st[5] : undef];
                } else {
                    $err = $!;
                }
            }
        } else {
            die "BUG: Unknown step command: $step->[0]";
        }
        if ($err) {
            if ($rollback) {
                die "Failed rollback step $i of 0..".(@$steps-1).": $err";
            } else {
                $log->tracef("Step failed: $err, performing rollback (%s)...",
                             $undo_steps);
                $rollback = $err;
                $steps = $undo_steps;
                redo STEPS;
            }
        }
    }
    return [500, "Error (rollbacked): $rollback"] if $rollback;

    my $meta = {};
    if ($undo_action =~ /^(re)?do$/) { $meta->{undo_data} = $undo_steps }
    elsif ($undo_action eq 'undo')   { $meta->{redo_data} = $undo_steps }
    $log->tracef("meta: %s", $meta);
    return [@$steps ? 200 : 304,
            @$steps ? "OK" : "Nothing done",
            undef,
            $meta];
}

1;


=pod

=head1 NAME

Setup::File - Ensure file (non-)existence, mode/permission, and content

=head1 VERSION

version 0.04

=head1 SYNOPSIS

 use Setup::File 'setup_file';

 # simple usage (doesn't save undo data)
 my $res = setup_file path => '/etc/rc.local',
                      should_exist => 1,
                      gen_content_code => sub { "#!/bin/sh\n" },
                      owner => 'root', group => 0,
                      mode => '+x';
 die unless $res->[0] == 200;

 # perform setup and save undo data (undo data should be serializable)
 $res = setup_file ..., -undo_action => 'do';
 die unless $res->[0] == 200;
 my $undo_data = $res->[3]{undo_data};

 # perform undo
 $res = setup_file ..., -undo_action => "undo", -undo_data=>$undo_data;
 die unless $res->[0] == 200;

 # state that file must not exist
 setup_file path => '/foo/bar', should_exist => 0;

=head1 DESCRIPTION

This module provides one function: B<setup_file>.

This module is part of the Setup modules family.

This module uses L<Log::Any> logging framework.

This module's functions have L<Sub::Spec> specs.

=head1 THE SETUP MODULES FAMILY

I use the C<Setup::> namespace for the Setup modules family, typically used in
installers (or other applications). The modules in Setup family have these
characteristics:

=over 4

=item * used to reach some desired state

For example, Setup::File::Symlink::setup_symlink makes sure a symlink exists to
the desired target. Setup::File::setup_file makes sure a file exists with the
correct content/ownership/permission.

=item * do nothing if desired state has been reached

=item * support dry-run (simulation) mode

=item * support undo to restore state to previous/original one

=back

This is the general logic flow of a typical setup function (for more details,
delve directly into source code): first, setup an empty list of steps. Then do a
series of state check. If a state is incorrect, add a step to fix that
situation. Proceed to the next state check. In the end, we end up with the list
of steps. Return 304 if list if empty (meaning all desired states have been
reached). Otherwise, perform each step consequently, while also append to list
of undo steps for each step. If an error is encountered, perform a roll back
(using the undo steps). If all steps have been done, return 200.

=head1 FUNCTIONS

None are exported by default, but they are exportable.

=head2 setup_file(%args) -> [STATUS_CODE, ERR_MSG, RESULT]


Ensure file (non-)existence, mode/permission, and content.

On do, will create file (if it doesn't already exist) and correct
mode/permission as well as content.

On undo, will restore old mode/permission/content, or delete the file again if
it was created by this function *and* its content hasn't changed since.

If given, -undo_hint should contain {tmp_dir=>...} to specify temporary
directory to save replaced file/dir. Temporary directory defaults to ~/.setup,
it will be created if not exists.

Returns a 3-element arrayref. STATUS_CODE is 200 on success, or an error code
between 3xx-5xx (just like in HTTP). ERR_MSG is a string containing error
message, RESULT is the actual result.

This function supports undo operation. See L<Sub::Spec::Clause::features> for
details on how to perform do/undo/redo.

This function supports dry-run (simulation) mode. To run in dry-run mode, add
argument C<-dry_run> => 1.

Arguments (C<*> denotes required arguments):

=over 4

=item * B<path>* => I<str>

Path to file.

File path needs to be absolute so it's normalized.

=item * B<allow_symlink>* => I<bool> (default C<0>)

Whether symlink is allowed.

If existing file is a symlink then if allow_symlink is false then it is an
unacceptable condition (the symlink will be replaced if replace_symlink is
true).

Note: if you want to setup symlink instead, use Setup::Symlink.

=item * B<check_content_code> => I<code>

Code to check content.

If unset, file will not be checked for its content. If set, code will be called
whenever file content needs to be checked. Code will be passed the file content
and should return a boolean value indicating whether content is acceptable.

=item * B<gen_content_code> => I<code>

Code to generate content.

If set, whenever a new file content is needed (e.g. when file is created or file
content reset), this code will be called to provide it. If unset, empty string
will be used instead.

Code will be passed the current content (or undef) and should return the new
content.

=item * B<group> => I<str>

Expected group.

=item * B<mode> => I<str>

Expected permission mode.

=item * B<owner> => I<str>

Expected owner.

=item * B<replace_dir>* => I<bool> (default C<1>)

Replace existing dir if it needs to be replaced.

=item * B<replace_file>* => I<bool> (default C<1>)

Replace existing file if it needs to be replaced.

=item * B<replace_symlink>* => I<bool> (default C<1>)

Replace existing symlink if it needs to be replaced.

=item * B<should_exist> => I<bool>

Whether file should exist.

If undef, file need not exist. If set to 0, file must not exist and will be
deleted if it does. If set to 1, file must exist and will be created if it
doesn't.

=back

=head1 SEE ALSO

L<Sub::Spec>, specifically L<Sub::Spec::Clause::features> on dry-run/undo.

Other modules in Setup:: namespace.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

