use 5.012;
use warnings;
use Archive::Zip  qw( :ERROR_CODES :CONSTANTS );
use Archive::Zip::MemberRead;
use Data::Dumper;
use Carp qw(confess);

my $input = $ARGV[0]  // './Qimba/taxonomy.qzv';
die unless (-e "$input");

my $info = getArtifactInfo(undef,$input);
say Dumper $info;
if ($info->{type} eq 'Visualization') {
    extractArtifact(undef, $input, $info->{uuid});
}
exit;

sub getArtifactInfo {
    my ($self, $file) = @_;
    my $uuid;
    my %info;
    unless ( -e "$file" ) {
        confess "Fatal error reading artifact <$file>: FILE NOT FOUND.\n";
    }
    my $zip = Archive::Zip->new();
    unless ( $zip->read( $file ) == AZ_OK ) {
        confess "Fatal error reading artifact <$file>: not a valid ZIP file.\n";
    }

    my @yaml_files = $zip->membersMatching( '^[a-z0-9-]+.metadata\.yaml' );
    
    if (scalar @yaml_files != 1) {
        confess "Qiime artifact <$file> is in an unsupported format.\n";
    }
    ($uuid) = $yaml_files[0]->{fileName}=~/^(.+).metadata\.yaml/;
    
    my $fh  = Archive::Zip::MemberRead->new($zip, $yaml_files[0]->{fileName});

    while (defined(my $line = $fh->getline()))  {
     my ($key, $value) = $line=~/(\w+):\s+(\S+)/;
     next unless defined $value;
     $info{$key} = $value;
    }
    if ($info{'uuid'} ne $uuid) {
        confess "Artifact <$file> has inconsitent UUID: $uuid detected and $info{uuid} read from metadata.\n";
    }
    return \%info;
}

sub extractArtifact {
    my ($self, $file, $uuid) = @_;
    unless ( -e "$file" ) {
        confess "Fatal error reading artifact <$file>: FILE NOT FOUND.\n";
    }
    my $zip = Archive::Zip->new();
    unless ( $zip->read( $file ) == AZ_OK ) {
        confess "Fatal error reading artifact <$file>: not a valid ZIP file.\n";
    }
    $zip->extractTree( "$uuid/data/", "$output_directory");
}
# Open

my $zip;
# Read a specific file (!)
my $c = 0;
my $fh  = Archive::Zip::MemberRead->new($zip, "c8ce60c8-3b6c-4f4a-8f95-e8f669fe9fa2/data/metadata.tsv");
while (defined(my $line = $fh->getline()))
{
    $c++;
    last if ($c > 10);
    print   $fh->input_line_number .'>'. " $line\n";
}

$zip->extractTree( 'c8ce60c8-3b6c-4f4a-8f95-e8f669fe9fa2/data/', '/tmp' );
 