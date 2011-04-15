
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'Module::Build' => '0.3601'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Ensure file (non-)existence, mode/permission, and content',
  'dist_author' => [
    'Steven Haryanto <stevenharyanto@gmail.com>'
  ],
  'dist_name' => 'Setup-File',
  'dist_version' => '0.01',
  'license' => 'perl',
  'module_name' => 'Setup::File',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'File::Copy::Recursive' => '0',
    'File::Path' => '2.07',
    'File::Slurp' => '0',
    'File::chdir' => '0',
    'File::chmod' => '0',
    'Log::Any' => '0',
    'Test::More' => '0.96',
    'UUID::Random' => '0',
    'perl' => '5.010000'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
