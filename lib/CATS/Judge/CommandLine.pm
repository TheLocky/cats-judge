package CATS::Judge::CommandLine;

use strict;
use warnings;

use Getopt::Long qw(GetOptions);

use CATS::ConsoleColor;

sub new {
    my ($class) = shift;
    my $self = { command => '', opts => {} };
    bless $self => $class;
}

sub command { $_[0]->{command} }
sub opts { $_[0]->{opts} }

sub usage
{
    my ($error) = @_;
    print "$error\n" if $error;
    my (undef, undef, $cmd) = File::Spec->splitpath($0);

    my $text = <<"USAGE";
Usage:
    $cmd <command> <options>

Commands:
    #serve#
    #install# --problem <zip_or_directory_or_name> [--force-install]
    #run# --problem <zip_or_directory_or_name> [--force-install]
        --run <file>... [--de <de_code>] [--testset <testset>]
        [--result text|html|none] [--result=columns <regexp>]
    #list# --url <url> [--system cats|polygon]
    #download# --problem <zip_or_directory_or_name> --url <url>
        [--system cats|polygon]
    #upload# --problem <zip_or_directory_or_name> --url <url>
        [--system cats|polygon]
    #config# --print <regexp> [--bare]
    #clear-cache# --problem <zip_or_directory_or_name>
    #help#|-?

Common options:
    --config-set <name>=<value> ...
    --db
    --format cats|polygon
    --verbose
USAGE
    ;
    $text =~ s/#(\S+)#/CATS::ConsoleColor::colored($1, 'bold white')/eg;
    print $text;
    exit;
}

my %commands = (
    '-?' => [],
    config => [
        '!print:s',
        'bare',
    ],
    'clear-cache' => [
        '!problem=s',
    ],
    download => [
        '!problem=s',
        'system=s',
        '!url=s',
    ],
    help => [],
    install => [
        'force-install',
        '!problem=s',
    ],
    list => [
        'system=s',
        '!url=s',
    ],
    run => [
        'de=i',
        'force-install',
        '!problem=s',
        'result=s',
        '!run=s@',
        'testset=s',
        'use-plan=s',
    ],
    serve => [],
    upload => [
        '!problem=s',
        'system=s',
        '!url=s',
    ],
);

sub get_command {
    my ($self) = @_;
    my $command = shift(@ARGV) // '';
    $command or usage('Command required');
    my @candidates = grep /^\Q$command\E/, keys %commands;
    @candidates == 0 and usage("Unknown command '$command'");
    @candidates > 1 and usage(sprintf "Ambiguous command '$command' (%s)", join ', ', sort @candidates);
    $self->{command} = $candidates[0];
}

sub get_options {
    my ($self) = @_;
    my $command = $self->command;
    GetOptions(
        $self->opts,
        'help|?',
        'db',
        'config-set=s%',
        'format=s',
        'verbose',
        map m/^\!?(.*)$/, @{$commands{$command}},
    ) or usage;
    usage if $command =~ /^(help| -?)$/ || defined $self->opts->{help};

    for (@{$commands{$command}}) {
        m/^!([a-z\-]+)/ or next;
        defined $self->opts->{$1} or usage("Command $command requires --$1 option");
    }

    for ($self->opts->{result}) {
        $_ //= 'text';
        /^(text|html|none)$/ or usage(q~Option --result must be either 'text', 'html' or 'none'~);
    }
    for ($self->opts->{'use-plan'}) {
        $_ //= 'all';
        /^(all|acm)$/ or usage(q~Option --plan must be either 'all', or 'acm'~);
    }
}

sub parse {
    my ($self) = @_;
    $self->get_command;
    $self->get_options;
}

1;
