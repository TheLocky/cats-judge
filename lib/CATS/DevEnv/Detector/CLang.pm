package CATS::DevEnv::Detector::CLang;

use strict;
use warnings;

use CATS::DevEnv::Detector::Utils;
use parent qw(CATS::DevEnv::Detector::Base);

sub name { 'CLang' }
sub code { '106' }

sub _detect {
    my ($self) = @_;
    env_path($self, 'clang');
    which($self, 'clang');
    env_path($self, 'clang++');
    which($self, 'clang++');
    drives($self, 'clang', 'clang');
    lang_dirs($self, 'clang', '', 'clang');
    lang_dirs($self, 'LLVM', '', 'clang');
    program_files($self, 'clang', 'clang');
    program_files($self, 'LLVM', 'clang');
    registry_glob($self, 'LLVM/LLVM/', 'bin', 'clang');
}

sub hello_world {
    my ($self, $clang) = @_;
    my $hello_world = <<'END'
#include <iostream>
int main() {
    std::cout<<"Hello World";
    return 0;
}
END
;
    my $source = write_temp_file('hello_world.cpp', $hello_world);
    my $exe = temp_file('hello_world.exe');
    run command => [ $clang, '-o', $exe, $source ] or return;
    my ($ok, undef, undef, $out) = run command => [ $exe ];
    $ok && $out->[0] eq 'Hello World';
}

sub get_version {
    my ($self, $path) = @_;
    my $v = `"$path" --version`;
    $v =~ /clang.+\s((?:\d+\.)+\d+)/ ? $1 : 0;
}

1;
