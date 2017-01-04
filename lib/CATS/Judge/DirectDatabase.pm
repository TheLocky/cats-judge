package CATS::Judge::DirectDatabase;

use strict;
use warnings;

use CATS::Config;
use CATS::Constants;
use CATS::DB qw(new_id $dbh);
use CATS::Testset;

use base qw(CATS::Judge::Base);

sub new_from_cfg {
    my ($class, $cfg) = @_;
    $class->SUPER::new(name => $cfg->name);
}

sub auth {
    my ($self) = @_;

    ($self->{id}, $self->{uid}, my $nick) = $dbh->selectrow_array(q~
        SELECT J.id, A.id, J.nick FROM judges J INNER JOIN accounts A ON J.account_id = A.id
        WHERE A.login = ?~, undef,
        $self->name);
    $self->{id} or die sprintf "unknown judge name: '%s'", $self->name;

    $nick eq $self->{name}
        or die "bad judge nick: $nick != $self->{name}";

    for (1..20) {
        $self->{sid} = $self->make_sid;
        if ($dbh->do(q~
            UPDATE accounts SET sid = ?, last_login = CURRENT_TIMESTAMP,
                last_ip = (
                    SELECT mon$remote_address
                    FROM mon$attachments M
                    WHERE M.mon$attachment_id = CURRENT_CONNECTION)
            WHERE id = ?~, undef,
            $self->{sid}, $self->{uid})
        ) {
            $dbh->commit;
            return;
        }
        sleep 1;
    }
    die "login failed\n";
}

sub is_locked { $_[0]->{lock_counter} }

sub set_request_state {
    my ($self, $req, $state, %p) = @_;
    $dbh->do(qq~
        UPDATE reqs SET state = ?, failed_test = ?, result_time = CURRENT_TIMESTAMP
        WHERE id = ? AND judge_id = ?~, {},
        $state, $p{failed_test}, $req->{id}, $self->{id});
    if ($state == $cats::st_unhandled_error && defined $p{problem_id} && defined $p{contest_id}) {
        $dbh->do(qq~
            UPDATE contest_problems SET status = ?
            WHERE problem_id = ? AND contest_id = ?~, {},
            $cats::problem_st_suspended, $p{problem_id}, $p{contest_id});
    }
    $dbh->commit;
}

sub was_pinged {
    my ($self) = @_;

    $self->{was_pinged};
}

sub select_request {
    my ($self) = @_;

    ($self->{was_pinged}, $self->{lock_counter}, my $current_sid, my $time_since_alive) = $dbh->selectrow_array(q~
        SELECT 1 - J.is_alive, J.lock_counter, A.sid, CURRENT_TIMESTAMP - J.alive_date
        FROM judges J INNER JOIN accounts A ON J.account_id = A.id WHERE J.id = ?~, undef,
        $self->{id});

    $current_sid eq $self->{sid}
        or die "killed: $current_sid != $self->{sid}";

    $dbh->do(q~
        UPDATE judges SET is_alive = 1, alive_date = CURRENT_TIMESTAMP WHERE id = ?~, undef,
        $self->{id}) if $self->{was_pinged} || $time_since_alive > $CATS::Config::judge_alive_interval / 24;
    $dbh->commit;

    return if $self->{lock_counter};

    my $sth = $dbh->prepare_cached(qq~
        SELECT
            R.id, R.problem_id, R.contest_id, R.state, CA.is_jury, C.run_all_tests,
            CP.status, S.fname, S.src, S.de_id
        FROM reqs R
        INNER JOIN contest_accounts CA ON CA.account_id = R.account_id AND CA.contest_id = R.contest_id
        INNER JOIN contests C ON C.id = R.contest_id
        INNER JOIN sources S ON S.req_id = R.id
        INNER JOIN default_de D ON D.id = S.de_id
        LEFT JOIN contest_problems CP ON CP.contest_id = R.contest_id AND CP.problem_id = R.problem_id
        WHERE R.state = ? AND
            (CP.status <= ? OR CA.is_jury = 1) AND
            D.code IN ($self->{supported_DEs}) AND (judge_id IS NULL OR judge_id = ?)
        ROWS 1~);
    my $req = $dbh->selectrow_hashref(
        $sth, { Slice => {} }, $cats::st_not_processed, $cats::problem_st_ready, $self->{id}) 
        or return;

    $dbh->do(q~
        UPDATE reqs SET state = ?, judge_id = ? WHERE id = ?~, {},
        $cats::st_install_processing, $self->{id}, $req->{id});
    $dbh->commit;

    $req;
}

sub save_log_dump {
    my ($self, $req, $dump) = @_;

    my $id = $dbh->selectrow_array(q~
        SELECT id FROM log_dumps WHERE req_id = ?~, undef,
        $req->{id});
    if (defined $id) {
        my $c = $dbh->prepare(q~UPDATE log_dumps SET dump = ? WHERE id = ?~);
        $c->bind_param(1, $dump, { ora_type => 113 });
        $c->bind_param(2, $id);
        $c->execute;
    }
    else {
        my $c = $dbh->prepare(q~INSERT INTO log_dumps (id, dump, req_id) VALUES (?, ?, ?)~);
        $c->bind_param(1, new_id);
        $c->bind_param(2, $dump, { ora_type => 113 });
        $c->bind_param(3, $req->{id});
        $c->execute;
    }
}

sub set_DEs {
    my ($self, $cfg_de) = @_;
    my $db_de = $dbh->selectall_arrayref(q~
        SELECT id, code, description, memory_handicap FROM default_de~, { Slice => {} });
    for my $de (@$db_de) {
        my $c = $de->{code};
        exists $cfg_de->{$c} or next;
        $cfg_de->{$c} = { %{$cfg_de->{$c}}, %$de };
    }
    delete @$cfg_de{grep !exists $cfg_de->{$_}->{code}, keys %$cfg_de};
    $self->{supported_DEs} = join ',', sort { $a <=> $b } keys %$cfg_de;
}

sub get_problem_sources {
    my ($self, $pid) = @_;
    my $problem_sources = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
        WHERE ps.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $pid);
    my $imported = $dbh->selectall_arrayref(q~
        SELECT ps.*, dd.code FROM problem_sources ps
            INNER JOIN default_de dd ON dd.id = ps.de_id
            INNER JOIN problem_sources_import psi ON ps.guid = psi.guid
        WHERE psi.problem_id = ? ORDER BY ps.id~, { Slice => {} },
        $pid);
    $_->{is_imported} = 1 for @$imported;
    [ @$problem_sources, @$imported ];
}

sub delete_req_details {
    my ($self, $req_id) = @_;
    $dbh->do(q~DELETE FROM req_details WHERE req_id = ?~, undef, $req_id);
    $dbh->commit;
}

sub insert_req_details {
    my ($self, $p) = @_;
    $dbh->do(
        sprintf(
            q~INSERT INTO req_details (%s) VALUES (%s)~,
            join(', ', keys %$p), join(', ', ('?') x keys %$p)
        ),
        undef, values %$p
    );
    $dbh->commit;
}

sub get_problem_tests {
    my ($self, $pid) = @_;
    $dbh->selectall_arrayref(q~
        SELECT generator_id, input_validator_id, rank, param, std_solution_id, in_file, out_file, gen_group
        FROM tests WHERE problem_id = ? ORDER BY rank~, { Slice => {} },
        $pid);
}

sub get_problem {
    my ($self, $pid) = @_;
    my $p = $dbh->selectrow_hashref(q~
        SELECT
            id, title, upload_date, time_limit, memory_limit,
            input_file, output_file, std_checker, contest_id, formal_input,
            run_method
        FROM problems WHERE id = ?~, { Slice => {} }, $pid);
    $p->{run_method} //= $cats::rm_default;
    $p;
}

sub is_problem_uptodate {
    my ($self, $pid, $date) = @_;
    scalar $dbh->selectrow_array(q~
        SELECT 1 FROM problems
        WHERE id = ? AND upload_date - 1.0000000000 / 24 / 60 / 60 <= ?~, undef,
        $pid, $date);
}

sub get_testset {
    my ($self, $rid, $update) = @_;
    CATS::Testset::get_testset($rid, $update);
}

sub finalize {
    CATS::DB::sql_disconnect;
}

1;
