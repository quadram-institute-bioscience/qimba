use 5.012;
use File::Basename;
use Data::Dumper;
my $art = './Qiime/hello.qza';
my @z = ('.qza', 'qza', 'qzv', '.qzv');
say Dumper \@z;
say basename($art, @z);
