use IPC::RunExternal;
 
my $external_command = 'sleep 22 && ls -r /'; # Any normal Shell command line
my $stdin = q{}; # STDIN for the command. Must be an initialised string, e.g. q{}.
my $timeout = 60; # Maximum number of seconds before forced termination.
my %parameter_tags = (print_progress_indicator => 1);
# Parameter tags:
# print_progress_indicator [1/0]. Output something on the terminal every second during
    # the execution, to tell user something is still going on.
# progress_indicator_char [*], What to print, default is '#'.
# execute_every_second [&], instead of printing the same everytime,
    # execute a function. The first parameters to this function is the number of seconds passed.
 
my ($exit_code, $stdout, $stderr, $allout);
#($exit_code, $stdout, $stderr, $allout)
#        = runexternal($external_command, $stdin, $timeout, \%parameter_tags);
 
# Parameter tags opened:
#($exit_code, $stdout, $stderr, $allout)
#        = runexternal($external_command, $stdin, $timeout, { progress_indicator_char => q{#} });


# Print `date` at every 10 seconds during execution
my $print_date_function = sub {
    my $secs_run = shift;
    if($secs_run % 10 == 0) {
	my $c = int($secs_run / 10);
 	my $date = `/bin/date +"%Y-%m-%d %H:%M:%S"`;
	chomp $date;
        print STDERR "\r", '~' x 10, "\t<$c> | $date | $secs_run\r";
    }


};
($exit_code, $stdout, $stderr, $allout) = runexternal($external_command, $stdin, $timeout,
        { execute_every_second => $print_date_function,
            print_progress_indicator => 1,
            progress_indicator_char => q{#},

        });

print ">>>
Exit: $exit_code
Out:  $stdout
---
Err:  $stderr
---
";
