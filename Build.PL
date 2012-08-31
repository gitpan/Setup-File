
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "File::Path" => "2.07",
    "File::chdir" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.96",
    "Test::Perinci::Tx::Manager" => "0.31",
    "autodie" => 0
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Setup file (existence, mode, permission, content)",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "Setup-File",
  "dist_version" => "0.16",
  "license" => "perl",
  "module_name" => "Setup::File",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "File::Slurp" => 0,
    "File::Trash::Undoable" => "0.06",
    "File::chmod" => 0,
    "Lchown" => 0,
    "Log::Any" => 0,
    "Rinci" => "v1.1.28",
    "SHARYANTO::File::Util" => "0.27",
    "Setup" => "v1.0.2",
    "perl" => "5.010000"
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
