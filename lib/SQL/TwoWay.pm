package SQL::TwoWay;
use strict;
use warnings FATAL => 'recursion';
use 5.010001; # Named capture
our $VERSION = "0.01";
use Carp ();

use parent qw(Exporter);

our @EXPORT = qw(two_way);

our ($TOKEN_STR2ID, $TOKEN_ID2STR);
BEGIN {
    $TOKEN_STR2ID = +{
        VARIABLE => 1,
        SQL      => 2,
        IF       => 3,
        ELSE     => 4,
        END_     => 5,
    };
    $TOKEN_ID2STR = +{ reverse %$TOKEN_STR2ID };
}
use constant $TOKEN_STR2ID;

sub new {
    my $class = shift;
    bless {
        ast => undef,
    }, $class;
}

sub token2str {
    $TOKEN_ID2STR->{+shift}
}

sub two_way {
    my ($sql, $params) = @_;

    my $tokens = tokenize_two_way($sql);
    my $ast = parse_two_way($tokens);
    my ($sql, @binds) = process_two_way($ast, $params);
    return ($sql, @binds);
}

sub process_two_way {
    my ($ast, $params) = @_;
    my ($sql, @binds);
    for my $node (@$ast) {
        if ($node->[0] eq IF) {
            my $name = $node->[1];
            unless (exists $params->{$name}) {
                Carp::croak("Unknown parameter for IF stmt: $name");
            }
            if ($params->{$name}) {
                my ($is, @ib) = process_two_way($node->[2], $params);
                $sql .= $is;
                push @binds, @ib;
            } else {
                my ($is, @ib) = process_two_way($node->[3], $params);
                $sql .= $is;
                push @binds, @ib;
            }
        } elsif ($node->[0] eq VARIABLE) {
            $sql .= '?';
            my $name = $node->[1];
            unless (exists $params->{$name}) {
                Carp::croak("Unknown parameter: $name");
            }

            push @binds, $params->{$name};
        } elsif ($node->[0] eq SQL) {
            $sql .= $node->[1];
        } else {
            Carp::croak("Unknown node: " . token2str($node->[0]));
        }
    }
    return ($sql, @binds);
}

=for bnf

    if : /* IF $var */
    else : /* ELSE */
    end : /* END */
    variable : /* $var */
    sql : .

    root = ( stmt )+
    stmt = sql | variable | if_stmt
    if_stmt = "IF" statement+ "ELSE" statement+ "END"
            | "IF" statement+ "END"

=cut

sub parse_two_way {
    my ($tokens) = @_;
    my @ast;
    while (@$tokens > 0) {
        push @ast, _parse_stmt($tokens);
    }
    return \@ast;
}

sub _parse_statements {
    my ($tokens) = @_;

    my @stmts;
    while (@$tokens && $tokens->[0]->[0] ~~ [SQL, VARIABLE, IF]) {
        push @stmts, _parse_stmt($tokens);
    }
    return \@stmts;
}

sub _parse_stmt {
    my ($tokens) = @_;

    if ($tokens->[0]->[0] eq SQL || $tokens->[0]->[0] eq VARIABLE) {
        my $token = shift @$tokens;
        return [
            $token->[0],
            $token->[1]
        ];
    } elsif ($tokens->[0]->[0] eq IF) {
        return _parse_if_stmt($tokens);
    } else {
        Carp::croak("Unexpected token: " . token2str($tokens->[0]->[0]));
    }
}

sub _parse_if_stmt {
    my ($tokens) = @_;

    # IF
    my $if = shift @$tokens;

    # Parse statements
    my $if_block = _parse_statements($tokens);

    # ELSE block
    my $else_block = [];
    if ($tokens->[0]->[0] eq ELSE) {
        shift @$tokens; # remove ELSE
        $else_block = _parse_statements($tokens);
    }

    # And, there is END_
    unless ($tokens->[0]->[0] eq END_) {
        Carp::croak("Unexpected EOF");
    }
    shift @$tokens; # remove END_

    return [
        IF, $if->[1], $if_block, $else_block
    ];
}

sub tokenize_two_way {
    my $sql = shift;

    my @ret;
    $sql =~ s!
        # Variable /* $var */3
        (
            /\* \s+ \$ (?<variable> [A-Za-z0-9_-]+) \s+ \*/
            (?: "[^"]+" | -? [0-9.]+ )
        )
        |
        (?:
            /\* \s+ IF \s+ \$ (?<ifcond> [A-Za-z0-9_-]+) \s+ \*/
        )
        |
        (?<else>
            /\* \s+ ELSE \s+ \*/
        )
        |
        (?<end>
            /\* \s+ END \s+ \*/
        )
        |
        # Normal SQL strings
        (?<sql1> [^/]+ )
        |
        # Single slash character
        (?<sql2> / )
    !
        if (defined $+{variable}) {
            push @ret, [VARIABLE, $+{variable}]
        } elsif (defined $+{ifcond}) {
            push @ret, [IF, $+{ifcond}]
        } elsif (defined $+{else}) {
            push @ret, [ELSE]
        } elsif (defined $+{end}) {
            push @ret, [END_]
        } elsif (defined $+{sql1}) {
            push @ret, [SQL, $+{sql1}]
        } elsif (defined $+{sql2}) {
            push @ret, [SQL, $+{sql2}]
        } else {
            Carp::croak("Invalid sql: $sql");
        }
    !gex;

    return \@ret;
}

1;
__END__

=head1 NAME

SQL::TwoWay - It's new $module

=head1 SYNOPSIS

    use SQL::TwoWay;

=head1 DESCRIPTION

SQL::TwoWay is ...

=head1 LICENSE

Copyright (C) tokuhirom

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

tokuhirom E<lt>tokuhirom@gmail.comE<gt>

