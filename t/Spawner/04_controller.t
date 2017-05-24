use strict;
use warnings;

use File::Spec;
use constant FS => 'File::Spec';

use FindBin qw($Bin);

BEGIN { require File::Spec->catdir($Bin, 'Common.pm'); Common->import; }

use Test::More tests => 5;
use CATS::Spawner::Const ':all';

run_subtest 'Empty controller', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $empty = compile('empty.cpp', "empty$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1, idle_time_limit => 1, deadline => 5 }, [
        program($empty, [ 1 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' }),
    ]);
    is $r->[0]->{exit_status}, 1, 'controller exit status';

    clear_tmpdir;
};

run_subtest 'Empty agent', compile_plan * 2 + items_ok_plan(2) + 2, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $empty = compile('empty.cpp', "empty$exe", $_[0] - compile_plan);

    my $r = run_sp_multiple({ time_limit => 1, deadline => 5 }, [
        program($sc, [ 1 ], { controller => 1, idle_time_limit => 3 }),
        program($empty, [ 2 ], { stdin => '*0.stdout', stdout => '*0.stdin', idle_time_limit => 1 }),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1TERMINATED' ], 'controller result';
    is $r->[1]->{exit_status}, 2, 'agent exit status';

    clear_tmpdir;
};

run_subtest 'Controller time limit', compile_plan * 2 + items_ok_plan(2), sub {
    my $while = compile('while.cpp', "while$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, idle_time_limit => 2}, [
        program($while, undef, { controller => 1 })->set_expected_tr($TR_TIME_LIMIT),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' }),
    ]);

    clear_tmpdir;
};

run_subtest 'Agent time limit', compile_plan * 2 + items_ok_plan(2) + 1, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $while = compile('while.cpp', "while$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1}, [
        program($sc, [ 1 ], { controller => 1, idle_time_limit => 2 }),
        program($while, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_TIME_LIMIT),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1TERMINATED' ], 'controller result';

    clear_tmpdir;
};

run_subtest 'Simple controller', compile_plan * 2 + items_ok_plan(2) + items_ok_plan(3) + items_ok_plan(4) + 3, sub {
    my $sc = compile('simple_controller.cpp', "sc$exe", $_[0]);
    my $pipe = compile('pipe.cpp', "pipe$exe", $_[0] - compile_plan);

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($sc, [ 1 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1OK' ], 'controller result';

    clear_tmpdir('*.txt', '*.tmp');

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($sc, [ 2, 1 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '2OK', '1OK' ], 'controller result';

    clear_tmpdir('*.txt', '*.tmp');

    run_sp_multiple({ time_limit => 1, idle_time_limit => 1 }, [
        program($sc, [ 1, 3, 2 ], { controller => 1 }),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
        program($pipe, undef, { stdin => '*0.stdout', stdout => '*0.stdin' })->set_expected_tr($TR_CONTROLLER),
    ]);
    is_deeply $spr->stderr_lines_chomp, [ '1OK', '3OK', '2OK' ], 'controller result';

    clear_tmpdir;
};



# +1
# a do nothing
# c TL
# c 1S# | 1W# and return
# c #S to a TL
# a IL
# c W# to terminated
# check I#
# c write before W#
# c + empty : W# sleep W# (read T#)
