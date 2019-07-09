package QimbaHelper;
use 5.014;
use File::Copy;
use warnings;
use Term::ANSIColor;
use Data::Dumper;
use Text::CSV;
use Carp qw(cluck confess);
use File::Spec::Functions;
use Cwd 'abs_path';
use FASTX::Reader;
use File::Basename;
use Archive::Zip  qw( :ERROR_CODES :CONSTANTS );
use Archive::Zip::MemberRead;
$QimbaHelper::VERSION = 0.1;

#ABSTRACT: Helper functions for 16S analyses

sub new {
    my ($class, $args) = @_;
    my $self = {
        debug   => $args->{debug},
        fortag  => $args->{fortag},
        revtag  => $args->{revtag},
        unexpected_files => 0,

    };
    my $object = bless $self, $class;

    return $object;
}

=head2 QimbaHelper object

  - samples_num
  - reads_num

  - metadata -> hash of SAMPLE_IDs -> attributes
        '<Sample>' => {
                       'DaysSinceExperimentStart' => '0',
                       'Subject' => 'subject-1',
                       'LinkerPrimerSequence' => 'GTGCCAGCMGCCGCGGTAA',
                       'Day' => '28',
                       ...

  - samples
          '<Sample>' => {
                       'forward' => 'reads/Mouse_R1.fq.gz',
                       'reverse' => 'reads/Mouse_R2.fq.gz'
                     },

  - counts -> <Sample> -> {reads}

=cut

sub loadMetadata {
    my ($self, $file) = @_;
    my @col;
    my $samples;
    my $csv = Text::CSV->new ({
      binary    => 1,
      auto_diag => 1,
      sep_char  => "\t"    # not really needed as this is the default
    });

    #SampleID, BarcodeSequence, LinkerPrimerSequence, BodySite, Year, Month, Day, Subject, ReportedAntibioticUsage, DaysSinceExperimentStart, Description
    #q2:types, categorical, categorical, categorical, numeric, numeric, numeric, categorical, categorical, numeric, categorical

    open(my $data, '<:encoding(utf8)', $file) or die "Could not open '$file' $!\n";
    my $c = 0;
    my $counter = 0;
    while (my $fields = $csv->getline( $data )) {
        $c++;
        if ($c == 1) {
            if ($fields->[0] ne '#SampleID') {
                confess "Metadata first field is not 'SampleID': we require a strict Qiime2 metadata file.\n";
            } else {
                $fields->[0] =~s/^#//;
                @col = @{$fields};

            }
        } elsif ($c == 2) {
            if ($fields->[0] !~/q2:types/) {
                confess "Metadata second row is not '#q2:types': we require a strict Qiime2 metadata file.\n";
            }
        } else{
            my $i = 0;
            next unless length($fields->[0]);
            $counter++;
            for my $c (@{ $fields }) {
                my $id = $col[$i];
                $samples->{$fields->[0]}->{$id} = $c;
                $i++;
            }
        }


    }
    $self->{samples_num} = $counter;
    $self->{metadata} = $samples;
    return $samples;

}

sub writeManifest {
    my ($self, $output) = @_;
    if (defined $self->{manifest}) {
        open my $OUT, '>', "$output" || confess "Unable to writeManifest() to $output\n";
        print {$OUT} $self->{manifest};
        return $self->{manifest};
    } else {
        confess "Writing manifest failed: manifest not found (run loadRead before)\n";
    }
}

sub loadReads {
    my ($self, $input_dir) = @_;

    opendir(my $DIR,$input_dir);
    my @dir = readdir($DIR);

    my $manifest = 'sample-id,absolute-filepath,direction'."\n";

    foreach my $id (sort keys %{ $self->{metadata} }) {
        my $match = 0;
        foreach my $filename (sort @dir) {

            if ($filename=~/$id/) {
                my $path =abs_path(catfile($input_dir, $filename));

                my $tag = undef;

                if ($filename=~/$self->{fortag}/) {
                    $tag = 'forward';
                } elsif ($filename=~/$self->{revtag}/) {
                    $tag = 'reverse';
                } else {
                    confess "File <$filename> has no forward/reverse tag\n";
                }
                $self->{samples}->{$id}->{$tag} = $path;
                $manifest .= "$id,$path,$tag\n";
                $self->{reads_num}++;
                $match++;
                if ($tag eq 'forward') {
                    my $seq_num = _fqcount($path);
                    $self->{counts}->{$id}->{reads} = $seq_num;
                }
            }
        }

        if ($match == 0) {
            # No file contained $id
            $self->{unexpected_files}++;
            confess("Sample <$id> has no files in <$input_dir>");
        } elsif ($match > 2) {
            # Expecting up to two files (R1 R2)
            confess "More than one file matches $id\n";
        }
    }

    $self->{manifest} = $manifest;

}

sub sampleCounts {
    my ($self) = @_;
    my $stats = '';
    foreach my $sample (sort keys %{ $self->{metadata} }) {
        $stats .= "$sample\t". $self->{counts}->{$sample}->{reads}. "\n";
    }
    return $stats;
}
sub combineUniques {
    my $opt_size_tag = ';size=';
    my $prefix = 'seq';
    my %uniques;
    my %names;
    my ($self,  $output_file, @files) = @_;
    open my $OUT, '>', "$output_file" || die "[combine_uniques]\tUnable to write to <$output_file>\n";
    foreach my $input_file (@files) {
        if (! -e "$input_file") {
            say STDERR "[combineUniques] Skipping <$input_file>: not found";
            next;
        }
        my $r = FASTX::Reader->new( {filename => "$input_file" });
        while (my $s = $r->getRead() ) {
            #>Uniq1;size=8993;
            if ($s->{name} =~/^(.+?)$opt_size_tag([\d+]+)/) {
                $uniques{ $s->{seq} } += $2;
                push( @{ $names{ $s->{seq} } }, $1);

            } else {
                confess "Sequence name [$s->{name}] has no valid size identifier [$opt_size_tag]\n";
            }

        }
    }

    my $counter = 0;
    foreach my $sequence (sort { $uniques{$b} <=> $uniques{$a} } keys %uniques) {
        $counter++;
        #my $name = join('_', @{ $names{$sequence}});
        my $name = $prefix . $counter;
        print {$OUT} ">", $name, $opt_size_tag, $uniques{$sequence}, "\n", $sequence, "\n";
    }
}


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
sub makeReportIndex {
  my ($self, $dir) = @_;
  my $file = catfile($dir, 'index.html');
  my $html_list = "
  <html>
  <head>
  <style>
    <!--
      body {font-family: Helvetica;}
    -->
  </style>
  </head>
  <body><p><img src=\"qiime2-rect-200.png\"</p><h1>Qiime 2 Reports</h1>
  <ul>\n";
  open my $out, '>', $file || confess "Unable to create index file <$file>\n";
  foreach my $report (@{ $self->{visualizations} }) {
    my $report_name = ucfirst( $report );
    $report_name =~s/[-_]/ /g;
    copy catfile($dir, "qiime2-rect-200.png"), catdir(catdir($report, "q2templateassets"), "img");
    $html_list .= qq(<li><a href="$report/index.html">$report_name</li>\n);
  }
  $html_list .= "</ul>\n";
  say {$out} $html_list;
}
sub extractArtifact {
    my ($self, $file, $outpath, $dirname) = @_;
    my @ext = ('.qza', '.qzv');
    $dirname = basename($file, @ext) if (not defined $dirname);

    $outpath = $self->{report_dir} if (not defined $outpath);
    my $dest_dir = catdir($outpath, $dirname);

    if ($self->{debug}) {
      say STDERR "[extractArtifact] $file -> $outpath > $dirname ";
    }
    unless ( -e "$file" ) {
        confess "Fatal error reading artifact <$file>: FILE NOT FOUND.\n";
    }
    my $info = getArtifactInfo($self, $file);
    my $uuid = $info->{uuid};
    my $zip = Archive::Zip->new();
    unless ( $zip->read( $file ) == AZ_OK ) {
        confess "Fatal error reading artifact <$file>: not a valid ZIP file.\n";
    }
    if (not -d "$outpath" or -d "$dest_dir") {
      confess "[extractArtifact] failed: output directory (parent) not found: '$outpath' OR destination directory '$dest_dir' found (should be created).\n";
    } else {
      mkdir "$dest_dir";
      $zip->extractTree( "$uuid/data/", "$dest_dir");
      push(@{ $self->{visualizations}}, $dirname) if (-e "$dest_dir/index.html");
    }

}

sub getArtifactInfoLegacy {
    # UUID:        5dd64ef3-cca9-4611-bb74-d0dc5111ab71
    # Type:        FeatureTable[Frequency]
    # Data format: BIOMV210DirFmt
    my $info;
    my ($self, $file) = @_;
    my @data = qx(qiime tools peek "$file");
    foreach my $line (@data) {
        if ($line=~/(\w+):\s+(.+)$/) {
            $info->{ lc($1) } = $2;

        }
    }
    # [uuid, type, format]
    return $info;
}

sub _fqcount {
    my ($file) = @_;
    my $r = FASTX::Reader->new({ filename => "$file" });
    my $c = 0;
    while (my $s = $r->getFastqRead() ) {
        $c++;
    }
    return $c;
}

sub _fastacount {
    my ($file) = @_;
    my $r = FASTX::Reader->new({ filename => "$file" });
    my $c = 0;
    my $min = undef;
    my $max = undef;
    my $sum = 0;

    while (my $s = $r->getRead() ) {
        $c++;
        my $l = length($s->{seq});
        $sum += $l;
        unless (defined $min) {
            $min = $l;
            $max = $l;
        }
        $min =  $l if ($l < $min);
        $max =  $l if ($l > $max);

    }
    my $avg = undef;
    $avg = sprintf("%.5f", $sum / $c) if ($c);
    return ($c, $min, $max, $avg);
}
1;
