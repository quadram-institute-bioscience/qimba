#rel/usr/bin/env perl
use 5.012;
use warnings;
use File::Basename;
use File::Find;
use File::Spec;
use Data::Dumper;
my $dir = $ARGV[0];

getData($dir);
sub getData {
	my @metadata;
	my %fastq_dir;
	my $finder = sub  {
		if ($File::Find::name=~/(metadata|mapping).*\.(txt|tsv|csv)$/) {
		  push(@metadata, $File::Find::name);
		} elsif  ($File::Find::name=~/\.fastq(\.gz)?$/) {
		  $fastq_dir{ dirname($File::Find::name) }++;
		}
	};
	find(\&{$finder}, "$dir");
	say Dumper \%fastq_dir;
	say Dumper \@metadata;
}
