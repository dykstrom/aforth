#!/usr/bin/env perl
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Times a list of jobs and prints the best wall clock each one reached, in
# milliseconds with three decimals, one per line in the order given.
#
# Usage: timeit.pl REPEATS JOBFILE
#
# JOBFILE holds one job per line: an input file, a tab, and the command to run
# on it.
#
# One repeat runs every job once, and the answer for a job is the best it ever
# reached. Interleaving is the point of the file: a machine that drifts -- a
# core that clocks down, another process that wakes up, a thermal limit that
# arrives -- drifts under all the jobs rather than under whichever happened to
# be timed while it lasted. Timing one build to completion and then the next
# measures the machine as much as the builds.
#
# The order rotates by one job on each repeat, so that no job is always the one
# that runs first out of idle or last into a warm machine. Interleaving alone
# leaves that position fixed, and on a machine whose clock moves over the
# seconds a repeat takes, a fixed position is a fixed bias.
#
# The command is forked and exec'd directly rather than handed to a shell, so
# the figure is the benchmarked process and not a shell as well. The input file
# becomes its standard input; its output and its errors are discarded, because
# a Forth that writes a banner or an ok prompt would otherwise be timed writing
# to a pipe nobody reads.
#
# The best of several runs rather than the mean: the quantity wanted is how
# long the work takes, and every disturbance -- a timer interrupt, another
# process, a migration to an efficiency core -- only ever adds. See
# docs/system/benchmark.md.
#
# perl rather than a C program, because the test suite already depends on perl
# on both platforms and the build is meant to stay make and clang alone.

use strict;
use warnings;

# Core Perl, but Debian splits it out of perl-base, so a slim container has to
# install the perl package to get it. docker/Dockerfile does.
BEGIN {
    eval { require Time::HiRes; Time::HiRes->import('time'); 1 }
        or die "timeit.pl: no Time::HiRes; install the perl package\n";
}

my ($reps, $jobfile) = @ARGV;
die "usage: timeit.pl REPEATS JOBFILE\n"
    unless defined $jobfile && defined $reps && $reps =~ /^[0-9]+$/ && $reps > 0;

open my $fh, '<', $jobfile or die "$jobfile: $!\n";
my @jobs;
while (<$fh>) {
    chomp;
    next unless length;
    my ($in, $cmd) = split /\t/, $_, 2;
    die "$jobfile:$.: no tab\n" unless defined $cmd;
    push @jobs, [$in, $cmd];
}
close $fh;
die "$jobfile: no jobs\n" unless @jobs;

my @best = (undef) x @jobs;
for my $rep (1 .. $reps) {
    for my $k (0 .. $#jobs) {
        my $i = ($k + $rep - 1) % @jobs;
        my ($in, $cmd) = @{ $jobs[$i] };
        my $t0  = time;
        my $pid = fork;
        die "fork: $!\n" unless defined $pid;
        if ($pid == 0) {
            open STDIN,  '<', $in         or die "$in: $!\n";
            open STDOUT, '>', '/dev/null' or die "/dev/null: $!\n";
            open STDERR, '>', '/dev/null' or die "/dev/null: $!\n";
            exec $cmd;
            exit 127;
        }
        waitpid $pid, 0;
        die "$cmd: exited with status " . ($? >> 8) . "\n" if $?;
        my $ms = (time - $t0) * 1000;
        $best[$i] = $ms if !defined $best[$i] || $ms < $best[$i];
    }
}
printf "%.3f\n", $_ for @best;
