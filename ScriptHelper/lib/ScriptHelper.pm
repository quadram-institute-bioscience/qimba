package ScriptHelper;
use 5.014;
use warnings;
use Term::ANSIColor;
use Data::Dumper;
use File::Basename;
use Time::Piece;
use Time::HiRes qw(gettimeofday tv_interval clock_gettime clock_getres);
use IPC::RunExternal;
use Carp qw(cluck confess);
$ScriptHelper::VERSION = 0.1;

#ABSTRACT: Helper functions for CLI scripts

my $progress_function = sub {

  my $secs_run = shift;
  return if ($secs_run <= 0 or $secs_run % 2);
  my @spin = (
  ' -->     ',
  ' --->    ',
  ' ---->   ',
  '  ---->  ',
  '   ----> ',
  '    ---->',
  '     ----',
  ' >    ---',
  ' ->      ',
  );
  my $res = 10;

  my $i   = ($secs_run / 2) % 9;
  print STDERR "\r", ' ', $spin[ $i ], " | ", _fsec($secs_run), "\r";

  if ($secs_run % $res == 0) {
    my $c = int($secs_run / $res);
    #my $date = `/bin/date +"%H:%M:%S"`;
    #chomp $date;
    #print STDERR "\r", ' ' x $res, " | $date | ", _fsec($secs_run), "\r";
  }

  #print STDERR  " ", $spin[ $i ], "\r";


};

sub new {
    my ($class, $args) = @_;
    my $self = {
        debug   => $args->{debug},
        verbose => $args->{verbose},
        nocolor => $args->{nocolor},
        logfile => $args->{logfile},
        outdir  => $args->{outdir},
        force   => $args->{force},
        script_dir => dirname($0),
    };
    my $object = bless $self, $class;

    # Check output directory

    if (-d "$object->{outdir}") {
        if (not $self->{force}) {
            confess "Output directory found: this is not allowed at the moment [$object->{outdir}]";
        } else {
            $self->deb("Removing directory [--force]: $self->{outdir}");
            #$self->run({ cmd => qq(rm -rf "$self->{outdir}")});
            `rm -rf "$self->{outdir}"`;
            confess "Unable to remove $self->{outdir}\n" if ($?);
        }
    }
    $self->deb("Creating output directory: $self->{outdir}");
    mkdir($object->{outdir}) or confess "Unable to create output directory $object->{outdir}";

    my %parameter_tags = ();
    if (defined $object->{debug}) {
        %parameter_tags = (
        execute_every_second => $progress_function,
#        print_progress_indicator => 1,
#        progress_indicator_char => q{#},
      );
    }
    $object->{run_opt} = \%parameter_tags;

    if (defined $object->{logfile}) {
        $self->deb("Creating log file: $self->{logfile}");
        open(my $fh, '>', $object->{logfile}) or confess "Unable to write log file to $object->{logfile}";
        open(my $md, '>', $object->{logfile} . '.md') or confess "Unable to write log file to $object->{logfile}.md";
        $object->{LOG} = $fh;
        $object->{LOGMD} = $md;
        say $fh _timestamp(), "\tPipeline started";
    } else {
        confess "[ScriptHelper] Log file not supplied but required, initialize object iwht _logfile_ set.\n";
    }
    return $object;
}


sub load {
    my ($self, $dir) = @_;

}

sub run {
    my ($self, $run) = @_;

    # - $cmd:     command
    # - $title:   task title
    # - $canfail: ignore non-zero exit code
    # - @input:   list of non empty files required
    # - @output:  list of non empty files to be produced
    # -

    my $start_time = [gettimeofday];
    my $start_date = localtime->strftime('%m/%d/%Y %H:%M');

    unless (defined $run->{cmd}) {
        say Dumper $run;
        confess "No command provided";
    }
    if ( $run->{title} and not $run->{silent}) {
        $self->ver($run->{title}, "Shell");
    }

    # Check input *NON EMPTY* files
    foreach my $input_file (@{ $run->{input} }) {
        if (not -s "$input_file") {
            confess "[Run command] Execution of $run->{title} failed as a requested input file ($input_file) was not found or was empty.\nCommand: $run->{cmd}\n";
        }
    }

    my $log_title = $run->{title} // 'Shell execution';
    $self->logger("```\n$run->{cmd}\n```", $log_title);

    #my $cmd_output = `$run->{cmd}`;
    my $timeout = 60 * 60 * 48;
    my ($exit_code, $stdout, $stderr, $allout) = runexternal($run->{cmd}, q{}, $timeout, $self->{run_opt});
    print STDERR ' ' x 60, "\r" if ( (defined $self->{run_opt} or defined $self->{debug}) and  not $run->{silent});
    my $elapsed_time = tv_interval ( $start_time, [gettimeofday]);
    $run->{elapsed} = $elapsed_time;

    if ($exit_code == 1) {
      $run->{exitcode} = 0;
      $run->{msg} = 'OK'
    } elsif ($exit_code == 0 ) {
      $run->{exitcode} = 2;
      $run->{msg} = 'Timeout';
    } else {
      $run->{exitcode} = 1;
      $run->{msg} = 'Execution error';
    }

    $run->{output} = $stdout;
    $run->{stderr} = $stderr;

    if ($run->{exitcode} != 0 and $run->{canfail} != 1) {
        confess "Execution failed ($run->{msg}):\n[", $run->{cmd}, "]\n";
    }
    if ( not $run->{silent} ) {
      $self->deb($run->{cmd}, 'Command:');
      $self->deb('Finished in '. _fsec($run->{elapsed}) . "; returned $run->{msg}", 'Finished:');
    }
    return $run;
}

sub deb {
    my ($self, $message, $title) = @_;
    $title = $title // '';
    my @lines = split /\n/, $message;

    foreach my $l (@lines) {
        if ($self->{debug}) {
            say STDERR $self->_c('yellow'), "* $title\t",  $self->_c(), "$l",;
            if (defined $self->{LOG}) {
                say {$self->{LOG}} "[Debug $title]\t$l";
            }
        }
    }

}

sub ver {
    my ($self, $message, $title) = @_;

    my @lines = split /\n/, $message;

    $message = "\n" . $message if ($#lines > 1);


    if ($self->{verbose}) {
        print STDERR $self->_c('bold'), "[$title]\t", $self->_c() if defined $title;
        say STDERR "$message";
    }

    # ALWAYS LOG
    logger($self, $message, $title);

}

sub logger {
    my ($self, $message, $title) = @_;
    return 0 unless defined $self->{LOG};
    if (not defined $message) {
        say Dumper $self;
        say Dumper $message;
        confess "No message arrived to [logger]\n";
    }
    say {$self->{LOG}} "## $title" if defined $self->{LOG} and defined $title;
    say {$self->{LOG}} _timestamp(), ": $message" if defined $self->{LOG};
    say {$self->{LOG}} "" if defined $title;
}
sub getFileFromZip {
    my ($self, $file, $path) = @_;
    my $out = run($self, {
            cmd => qq(unzip -f "$file" "$path"),
            silent => 1,
        });
    return $out;
}
sub checkDependencies {
    my ($self, $dep_ref) = @_;

    foreach my $key (sort keys %{ $dep_ref } ) {
        confess "Command not found for dependency <$key>: " unless defined (${ $dep_ref }{$key}->{binary});

        if (-e $self->{script_dir}."/tools/${ $dep_ref }{$key}->{binary}") {
            ${ $dep_ref }{$key}->{binary} = "$self->{script_dir}/tools/${ $dep_ref }{$key}->{binary}";
        }

        my $test_cmd = qq(${ $dep_ref }{$key}->{"test"});
        $test_cmd =~s/{binary}/${ $dep_ref }{$key}->{binary}/g;
        my $cmd = qq($test_cmd 2>&1 | grep "${ $dep_ref }{$key}->{"check"}");
        my $check = run($self, {
            'cmd' => $cmd,
            'title' => qq(Checking dependency: <${ $dep_ref }{$key}->{"binary"}>),
            'canfail'    => 1,
            'nocache'     => 1,
        });
        die if not defined $check;
        if ($check->{exitcode} > 0) {
            print STDERR color('red'), "Warning: ", color('reset'), ${ $dep_ref }{$key}->{binary}, ' not found in $PATH, trying local binary', "\n" if ($self->{debug});
            ${ $dep_ref }{$key}->{binary} = "$self->{script_dir}/bin/" . ${ $dep_ref }{$key}->{binary};

            my $test_cmd = qq(${ $dep_ref }{$key}->{"test"});
            $test_cmd =~s/{binary}/${ $dep_ref }{$key}->{binary}/g;
            my $cmd = qq($test_cmd 2>&1 | grep "${ $dep_ref }{$key}->{"check"}");
            run($self, {
                        'cmd' => $cmd,
                        'title' => qq(Checking local dependency: <${ $dep_ref }{$key}->{"binary"}>),
                        'canfail'    => 0,
                        'nocache'     => 1,
                    });
        }


    }

    return $dep_ref;
}

## INTERNAL SUBROUINES


sub _fsec {

  my $time = shift;
  my $days = int($time / 86400);
   $time -= ($days * 86400);
  my $hours = int($time / 3600);
   $time -= ($hours * 3600);
  my $minutes = int($time / 60);
  my $seconds = $time % 60;

  $days = $days < 1 ? '' : $days .'d ';
  $hours = $hours < 1 ? '' : $hours .'h ';
  $minutes = $minutes < 1 ? '' : $minutes . 'm ';
  $time = $days . $hours . $minutes . $seconds . 's';
  return $time;


}
sub _timestamp {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d%02d%02d %02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);

    return $nice_timestamp;
}
sub _c {
    # Return a color from Term::ANSIColor if color are enabled
    my ($self, $color) = @_;
    $color = 'reset' unless ($color);
    if ( (not $self->{nocolor}) and (not $ENV{'NOCOLOR'}) ) {
        return Term::ANSIColor::color($color);
    } else {
        return;
    }
}
1;
