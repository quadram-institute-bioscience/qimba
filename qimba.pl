#!/usr/bin/env perl
use 5.016;
my  $PROGRAM = 'qimba';
my  $VERSION = '1.10';
use Getopt::Long;
use File::Spec;
use File::Spec::Functions;
use File::Copy;
use File::Find;
use File::Basename;
use FindBin qw($RealBin);
use lib "$RealBin/ScriptHelper/lib/";
use ScriptHelper;
use QimbaHelper;
use FASTX::Reader;
use Proch::N50;
use Data::Dumper;
use JSON::PP;
## Defaults
my $opt_trim       = 10;
my $opt_trunc_1    = 0;
my $opt_trunc_2    = 0;
my $opt_maxee      = 1.9;
my $opt_min_depth  = 10000;
my $opt_threads    = 4;
my $dbdir          = catdir("$RealBin", 'db');
my $q2db           = catfile("$dbdir", 'gg-13-8-99-515-806-nb-classifier.qza');
my $db_rdp         = catfile("$dbdir", 'rdp_16s_v16.fa');

my $opt_output_dir = catdir('Qimba');
my $opt_logfile;
my $opt_fortag     = '_R1';
my $opt_revtag     = '_R2';

# External dependencies

my $dependencies = {
	'u10'  => {
		binary  => 'usearch_10',
		test    => '{binary}',
		check   => 'usearch v10',
		message => 'Please, place USEARCH v10 binary named "usearch_10" in your path '.
						   'or in the "/tools" subdirectory of this script',

	},
	'qiime' => {
		binary  => 'qiime',
		test    => '{binary} --version',
		check   => 'q2cli version 2019.4',
		message => 'qiime 2 2019.4 is needed (different version can introduce unexpected errors). '.
				   			'Activate the environment if installed via conda',
		required=> 1,
	},
	'vsearch' => {
		binary  => 'vsearch',
		test    => '{binary} --version',
		check   => 'vsearch v2.7',
		message => 'VSEARCH 2.7 is required. Installation via Miniconda is recommended, '.
				   			'alternatively place the binary in the "/tools" subdirectory of this script',
	  required=> 1,
	}
};

# UNINITIALIZED PARAMETERS
my (
	$opt_input_dir,
	$opt_metadata,
	$opt_debug,
	$opt_verbose,
	$opt_nocolor,
	$opt_db,
	$opt_force,
	$opt_skip_qiime,
	$opt_skip_otu,
	$opt_very_short_qiime,
	$opt_autorun,
	$opt_nodocker,
);

my $GetOptions = GetOptions(
	'run|docker'           => \$opt_autorun,
	'noauto'               => \$opt_nodocker,
	'i|input-dir=s'        => \$opt_input_dir,
	'm|metadata|mapping=s' => \$opt_metadata,
	'min-depth=i'          => \$opt_min_depth,
	'o|output-dir=s'       => \$opt_output_dir,
	'r1tag=s'              => \$opt_fortag,
	'r2tag=s'              => \$opt_revtag,
	'l|logfile=s'          => \$opt_logfile,
	'd|debug'              => \$opt_debug,
	'v|verbose'            => \$opt_verbose,
	'force'                => \$opt_force,
	'db=s'                 => \$opt_db,
	'no-color'             => \$opt_nocolor,
	't|threads=i'          => \$opt_threads,
	'skip-qiime'           => \$opt_skip_qiime,
	'skip-otu'             => \$opt_skip_otu,
	'demoqiime'            => \$opt_very_short_qiime,
);

if ($opt_autorun and not $opt_nodocker){
	$opt_force = 1;
	($opt_input_dir, $opt_metadata, $opt_output_dir) = dockerPaths();
}
# No color
$opt_nocolor = 1     if ($ENV{'NO_COLOR'});
$ENV{'NO_COLOR'} = 1 if ($opt_nocolor);

my $json = JSON::PP->new->ascii->pretty->allow_nonref;
$opt_logfile = catfile("${opt_output_dir}", 'qimba.log');
usage(1) if (not defined $opt_input_dir or not defined $opt_metadata);


my $s = ScriptHelper->new({
	verbose => $opt_verbose,
	debug   => $opt_debug,
	nocolor => $opt_nocolor,
	logfile => $opt_logfile,
	outdir  => $opt_output_dir,
	force   => $opt_force,
});

my $otu_dir = catdir("$opt_output_dir", 'otu');
my $otu_sample_dir = catdir("$otu_dir", 'samples');
my $report_dir = catdir("$opt_output_dir", 'reports');
my $tools = $s->checkDependencies($dependencies);

my $QIMBA = QimbaHelper->new({
	debug      => $opt_debug,
	fortag     => $opt_fortag,
	revtag     => $opt_revtag,
	report_dir => $report_dir,
});

# OTU analysis: output directory

mkdir "$report_dir" || die "Unable to create reports directory: $report_dir.\n";
copy catfile("$dbdir", "qiime2-rect-200.png"), "$report_dir";
# Parse Qiime2 Metadata
my $metadata = $QIMBA->loadMetadata($opt_metadata);
$s->deb("Metadata loaded: " . $QIMBA->{samples_num} . " samples found");

# Load/Validate Reads from metadata
my $manifest_file_path = catfile($opt_output_dir, 'import.manifest');
my $reads = $QIMBA->loadReads($opt_input_dir);
my $manifest = $QIMBA->writeManifest( $manifest_file_path );

$s->ver($manifest, 'Manifest');
$s->deb("Read paths: " . $QIMBA->{reads_num} . " files found");
$s->deb("Read paths: " . $QIMBA->{unexpected_files} . " unexpected files found");
$s->ver($QIMBA->sampleCounts(), 'Read counts');

if ($tools->{u10}->{missing}) {
	$opt_skip_otu = 1;
	$s->ver("Skipping USEARCH: dependency not satisfied");
}
# Process single samples
# ========================

if (not $opt_skip_otu) {
	mkdir( $otu_dir );
	mkdir( $otu_sample_dir );
	my $all_fastq_files = "$otu_dir/all_samples.fq";
	$s->run({ cmd => qq(touch "$all_fastq_files"), title => 'Merged reads container initialization'});

	my @dereplicated_reads;
	foreach my $sample (sort keys %{ $QIMBA->{metadata} }) {
			my $file_R1 = $QIMBA->{samples}->{$sample}->{"forward"};
			my $file_R2 = $QIMBA->{samples}->{$sample}->{"reverse"};
			if (-e "$file_R1" and -e "$file_R2") {
				my ($derep) = run_sample_processor($file_R1, $file_R2, $otu_sample_dir, $sample, $all_fastq_files);
				push(@dereplicated_reads, $derep);

			} else {
				$s->ver("Skipping $sample: files not found ($file_R1 or $file_R2)");
			}
	}
	# OTUs
	my $dereplicated_file = catfile($otu_dir, 'dereplicated.fa');
	$QIMBA->combineUniques($dereplicated_file, @dereplicated_reads);
	run_dereplicated_processor($dereplicated_file, $all_fastq_files, $otu_dir);
}
# ================
#  QIIME 2
if (not $opt_skip_qiime) {
	run_qiime_2($manifest_file_path, $opt_output_dir, $opt_metadata);
	$QIMBA->{info}->{reads} = $QIMBA->getArtifactInfo("$opt_output_dir/reads.qza");
	$QIMBA->{info}->{stats} = $QIMBA->getArtifactInfo("$opt_output_dir/stats.qza");
	$QIMBA->{info}->{repseq} = $QIMBA->getArtifactInfo("$opt_output_dir/rep-seqs.qza");
	my $stats_uuid =  $QIMBA->{info}->{stats}->{uuid};
	my $stats  = $s->getFileFromZip("$opt_output_dir/stats.qza", "$stats_uuid/data/stats.tsv");
}
# ================



if ($opt_debug) {
	my $QimbaJson = $json->allow_blessed->convert_blessed->encode($QIMBA);
	$s->logger($QimbaJson, 'QIMBA_JSON');
}

sub run_dereplicated_processor {
	my ($der,$fastq_total, $out) = @_;

	my $sample_size = 100000;
	$s->run({
		title  => 'USEARCH OTU clustering',
		cmd    => qq($tools->{u10}->{binary} -cluster_otus "$der" -minsize 3 -otus "$out/otus.fa" -relabel Otu -uparseout "$out/otus.txt" ),
		});

	$s->run({
		title  => 'USEARCH ASV picking',
		cmd    => qq($tools->{u10}->{binary} -unoise3  "$der" -zotus "$out/asv.fa" ),
		});

	$s->run({
		title  => 'USEARCH Preparing OTU table',
		cmd    => qq($tools->{u10}->{binary} -otutab "$fastq_total" -otus "$out/otus.fa" -otutabout "$out/otu.table.raw" ),
		});
	$s->run({
		title  => 'USEARCH Preparing ASV table',
		cmd    => qq($tools->{u10}->{binary} -otutab "$fastq_total" -otus "$out/asv.fa" -otutabout "$out/asv.table.raw" ),
		});

	$s->run({ title => 'USEARCH normalize OTU table',
		cmd => qq($tools->{u10}->{binary} -otutab_norm "$out/otu.table.raw" -sample_size $sample_size -output "$out/otu.table.tsv"),
	});

	$s->run({ title => 'USEARCH normalize ASV table',
		cmd => qq($tools->{u10}->{binary} -otutab_norm "$out/asv.table.raw" -sample_size $sample_size -output "$out/asv.table.tsv"),
	});

	$s->run({
		title => 'USEARCH Taxonomy classification',
		cmd   => qq($tools->{u10}->{binary} -sintax "$out/otus.fa" -db "$db_rdp" -strand both   -tabbedout "$out/otu.taxonomy.txt" -sintax_cutoff 0.8),
	});

	$s->run({
		title => 'USEARCH Taxonomy summary: Genus',
		cmd   => qq($tools->{u10}->{binary}  -sintax_summary "$out/otu.taxonomy.txt" -otutabin "$out/otu.table.tsv" -rank g -output "$out/otu.genus.txt"),
	});
	$s->run({
		title => 'USEARCH Taxonomy summary: Phylym',
		cmd   => qq($tools->{u10}->{binary}  -sintax_summary "$out/otu.taxonomy.txt" -otutabin "$out/otu.table.tsv" -rank p -output "$out/otu.phylum.txt"),
	});


	# $s->run({

	# 	title => 'VSEARCH ASV table',
	# 	cmd   => qq($tools->{vsearch}->{binary} --threads $opt_threads --cluster_size "$der" --id 0.97     --strand plus --sizein --sizeout --fasta_width 0 --uc "$out/asv.vsearch.uc" --relabel OTU_     --centroids "$out/otu.vsearch.fa" --otutabout "$out/otu.vsearch.tsv" > "$out/vsearch-otutab.log" ),
	# })
}

sub run_sample_processor {

	my ($R1, $R2, $dir, $sample, $all_samples) = @_;
	my $MIN_OVERLAP = 25;
	my $MAX_DIFF    = 12;
	my $MAX_LEN     = 500;
	my $MIN_LEN     = 310;
	my $STRIP_LEFT  = 18;
	my $STRIP_RIGHT = 18;

	$s->run({
		input  => ["$R1", "$R2"],
		output => ["$dir/$sample.join.fq"],
		title  => "$sample: merging",
		cmd    => qq($tools->{'vsearch'}->{binary} --threads $opt_threads --no_progress --fastq_mergepairs "$R1" --reverse "$R2" --fastq_minovlen $MIN_OVERLAP --fastq_maxdiffs $MAX_DIFF --fastqout "$dir/$sample.join.fq" --fastq_eeout --fastq_maxee $opt_maxee ),
	});

	# Prepare all merged relabeled
	open my $OUT, '>>', "$all_samples" || die "[CombineMergedFastq] Unable to write to: <$dir/all_samples.join.fq>\n";
	my $reader = FASTX::Reader->new({ filename => "$dir/$sample.join.fq" });
	my $i = 0;
	while (my $s = $reader->getFastqRead()) {
		$i++;
		say {$OUT} '@', $sample , ".$i\n",
			$s->{seq} , "\n+\n", $s->{qual};
	}
	die "Looks like $all_samples is empty and should have $i sequences from $\n" if (! -s "$all_samples" and $i > 0);
	$s->run({
		input  => ["$dir/$sample.join.fq"],
		output => ["$dir/$sample.filtered.fasta"],
		title  => "$sample: filtering",
		cmd    => qq($tools->{'vsearch'}->{binary}  --threads $opt_threads --no_progress --fastq_filter "$dir/$sample.join.fq" --fastq_maxee $opt_maxee --fastq_minlen $MIN_LEN --fastq_maxlen $MAX_LEN --fastq_maxns 0 --fastq_stripleft  $STRIP_LEFT --fastq_stripright $STRIP_RIGHT  --fastaout "$dir/$sample.filtered.fasta" --fasta_width 0 ),
	});


	$s->run({
		input  => ["$dir/$sample.filtered.fasta"],
		output => ["$dir/$sample.derep.fasta", "$dir/$sample.derep.uc"],
		title  => "$sample: dereplicating",
		cmd    => qq($tools->{'vsearch'}->{binary}  --threads $opt_threads --no_progress        --derep_fulllength "$dir/$sample.filtered.fasta" --strand plus --output "$dir/$sample.derep.fasta" --sizeout --uc "$dir/$sample.derep.uc" --relabel "$sample" --fasta_width 0 ),
    });

    return "$dir/$sample.derep.fasta";
}

sub run_qiime_2 {
	my ($manifest, $out, $metadata) = @_;
	# IMPORT READS
	$s->run({
		title => "Importing reads",
		cmd =>  qq(qiime tools import --type SampleData[PairedEndSequencesWithQuality] ).
				qq( --input-path "$manifest" --output-path "$out/reads.qza" ).
				qq( --input-format  PairedEndFastqManifestPhred33),
	});

	if ($opt_very_short_qiime) {
		$QIMBA->extractArtifact("$out/reads.qza", "$out", 'test-reads');
		exit;
	}

	# DENOISE DADA2
	$s->run({
		title => "DADA2",
		cmd =>  qq(qiime dada2 denoise-paired --i-demultiplexed-seqs "$out/reads.qza" ).
				qq( --p-trim-left-f $opt_trim --p-trim-left-r $opt_trim ).
				qq( --p-trunc-len-f $opt_trunc_1 --p-trunc-len-r $opt_trunc_2 ).
				qq( --p-n-threads  $opt_threads --p-max-ee $opt_maxee ).
				qq( --o-representative-sequences "$out/rep-seqs.qza" --o-table "$out/table.qza" ).
	      qq( --o-denoising-stats "$out/stats.qza"),
	});
	$QIMBA->extractArtifact("$out/rep-seqs.qza", "$out");
	$QIMBA->extractArtifact("$out/table.qza", "$out");
	$s->run({
		title => 'Convert biom',
		cmd   => qq(biom convert --to-tsv -i "$out/table/feature-table.biom" -o "$out/table/feature-table.tsv" ),
	});



	# PHYLOGENY
	$s->run({
		title => "Phylogeny",
		cmd => qq(qiime phylogeny align-to-tree-mafft-fasttree ) .
				qq(  --i-sequences "$out/rep-seqs.qza" ) .
				qq(  --o-alignment "$out/aligned-rep-seqs.qza" ) .
				qq(  --o-masked-alignment "$out/masked-aligned-rep-seqs.qza"  ) .
				qq(  --o-tree "$out/unrooted-tree.qza"  ) .
				qq(  --o-rooted-tree "$out/rooted-tree.qza" ),
	});
	# CORE DIVERSITY

	$s->run({
		title => "Core diversity metrics",
		cmd =>  qq(qiime diversity core-metrics-phylogenetic ) .
				qq(	  --i-phylogeny "$out/rooted-tree.qza" ) .
				qq(	  --i-table "$out/table.qza" ) .
				qq(	  --p-sampling-depth "$opt_min_depth" ) .
				qq(	  --m-metadata-file "$metadata" ) .
				qq(	  --output-dir "$out/core-metrics-results" ),
	});

	$s->run({
		input => ["$q2db", "$out/rep-seqs.qza"],
		title => "Taxonomy classification",
		cmd   => qq(qiime feature-classifier classify-sklearn --i-classifier "$q2db" --i-reads "$out/rep-seqs.qza" --o-classification "$out/taxonomy.qza"),
	});

	$QIMBA->extractArtifact("$out/taxonomy.qza", "$out");


	# ––––––––––– VISUALIZATION –––––––––––––––––
	$s->run({
		title => "Taxonomy plot [visualization]",
		cmd   => qq(qiime taxa barplot --i-table "$out/table.qza" --i-taxonomy "$out/taxonomy.qza" --m-metadata-file "$opt_metadata" --o-visualization "$out/taxa-bar-plots.qzv"),
	});

	$s->run({
		title => "Taxonomy classification [visualization]",
		cmd   => qq(qiime metadata tabulate --m-input-file "$out/taxonomy.qza" --o-visualization "$out/taxonomy.qzv"),
	});

	#core-metrics-results/unweighted_unifrac_emperor.qzv: view | download
	#core-metrics-results/jaccard_emperor.qzv: view | download
	#core-metrics-results/bray_curtis_emperor.qzv: view | download
	#core-metrics-results/weighted_unifrac_emperor.qzv: view | download


	$QIMBA->extractArtifact("$out/taxonomy.qzv", "$report_dir");
	$QIMBA->extractArtifact("$out/taxa-bar-plots.qzv", "$report_dir");
	$QIMBA->extractArtifact("$out/core-metrics-results/unweighted_unifrac_emperor.qzv", "$report_dir");
	$QIMBA->extractArtifact("$out/core-metrics-results/jaccard_emperor.qzv", "$report_dir");
	$QIMBA->extractArtifact("$out/core-metrics-results/bray_curtis_emperor.qzv", "$report_dir");
	$QIMBA->extractArtifact("$out/core-metrics-results/weighted_unifrac_emperor.qzv", "$report_dir");

	$QIMBA->makeReportIndex("$report_dir");
		return 1;
}

sub usage {
	say STDERR<<END;

 -----------------------------------------------------------------------
  QIMBA - Quadram Institute MetaBarcoding Analysis $VERSION
 -----------------------------------------------------------------------

   -i, --input-dir DIR
            Input directory containing paired end FASTQ files

   -m, --metadata  FILE
            File with sample properties, in Qiime format

   -o, --output-dir DIR
            Output directory. Default: [$opt_output_dir]

   --help
	          Display full help page

 -----------------------------------------------------------------------

END
	die "Missing parameters\n" if ($_[0]);
	exit;
}


sub dockerPaths {
	my $outdir = '/output/';
	my $data_dir = '/data/';
	my $input_dir;
	my $metadata_file;

		my @metadata;
		my %fastq_dir;
		my $finder = sub  {
			if ($File::Find::name=~/(metadata|mapping).*\.(txt|tsv|csv)$/) {
			  push(@metadata, $File::Find::name);
			} elsif  ($File::Find::name=~/\.fastq(\.gz)?$/) {
			  $fastq_dir{ dirname($File::Find::name) }++;
			}
		};

		find(\&{$finder}, "$data_dir");
		$metadata_file = $metadata[0] if (scalar @metadata == 1);
		my @dirs = keys %fastq_dir;
		$input_dir = @dirs[0] if (scalar @dirs == 1);
		if (-d "$outdir" and defined $input_dir and defined $metadata_file) {
			return($input_dir, $metadata_file, $outdir)
		} else {
			say STDERR "QIMBA - DOCKER AUTORUN",
			'Usage: docker run -v $outputdir:/output -v $datadir:/data ...',
			"Docker paths not found:",
			"Output [$outdir] is required, and data dir [$data_dir] should contain a single metadata file",
			"(e.g. metadata.tsv) and a directory with FASTQ files. Use --nodocker to avoid autorun";
			exit;
		}
}



__END__




# our $dep = init($dependencies);
# $db = "$script_dir/db/rdp_16s_v16.fa" unless (defined $db);
# die " FATAL ERROR: Database not found <$db>\n" unless (-e "$db");
# deb_dump($dep);

# makedir($opt_output_dir);


# opendir(DIR, $opt_input_dir) or die "FATAL ERROR: Couldn't open input directory <$opt_input_dir>.\n";
# my %reads = ();

# # Scan all the .fastq/.fq file in directory, eventually unzip them
# # LOAD %reads{basename}{Strand}

# while (my $filename = readdir(DIR) ) {
# 	if ($filename =~/^(.+?).gz$/) {
# 		run({
# 			'description' => "Decompressing <$filename>",
# 			'command'     => qq(gunzip "$opt_input_dir/$filename"),
# 			'can_fail'    => 0,
# 		});
#     $filename =~s/.gz$//;

# 	} elsif ($filename !~/q$/) {
# 		deb("Skipping $filename: not a FASTQ file") if (! -d "$filename");
# 		next;
# 	}

# 	my ($basename) = split /$opt_fortag|$opt_revtag/, $filename;
# 	my $strand = $opt_fortag;
# 	$strand = $opt_revtag if ($filename =~/$opt_revtag/);

# 	if (defined $reads{$basename}{$strand}) {
# 		die "FATAL ERROR: There is already a sample labelled <$basename> [$strand]!\n $reads{$basename}{$strand} is conflicting with $filename"
# 	} else {
# 		$reads{$basename}{$strand} = $filename;
# 	}
# 	say STDERR "Adding $basename ($strand)" if ($opt_debug);
# }

# # Check reads
# ver("Input files:");
# foreach my $b (sort keys %reads) {
# 	if (defined $reads{$b}{$opt_fortag} and defined $reads{$b}{$opt_revtag}) {
# 		ver(" - $b", 'bold yellow');
# 	} else {

# 		die "FATAL ERROR: Sample '$b' is missing one of the pair ends: only $reads{$b}{$opt_fortag}$reads{$b}{$opt_revtag} found";
# 	}

# 	my $merged = "$opt_output_dir/${b}_merged.fastq";
# 	run({
# 		'command' => qq($dep->{u10}->{binary} -fastq_mergepairs "$opt_input_dir/$reads{$b}{$opt_fortag}" -fastqout "$merged" -relabel $b. > "$merged.log" ),
# 		'description' => qq(Joining pairs for $b),
# 		'count_seqs'  => "$merged",
# 		'min_seqs'    => $opt_min_merged_seqs,
# 	});

# 	# my $count = count_seqs("$merged");
# 	# say STDERR Dumper $count;
# 	# die;

# }

# my $all_merged   = "$opt_output_dir/all_reads_raw.fastq";
# my $all_stripped = "$opt_output_dir/all_reads_strp.fastq";
# my $all_filtered = "$opt_output_dir/all_reads_filt.fasta";
# my $all_unique   = "$opt_output_dir/all_reads_uniq.fasta";
# my $all_otus     = "$opt_output_dir/OTUs.fasta";
# my $all_zotus    = "$opt_output_dir/ASVs.fasta";


# run({
# 	'command'     => qq(cat "$opt_output_dir"/*_merged.fastq > "$all_merged"),
# 	'description' => 'Combining all reads',
# 	'outfile'     => $all_merged,
# });


# # Strip primers (V4F is 19, V4R is 20)
# run({
# 	'command' => qq($dep->{u10}->{binary} -fastx_truncate "$all_merged" -stripleft $opt_left_primerlen -stripright $opt_right_primerlen -fastqout "$all_stripped"),
# 	'description' => "Stripping primers ($opt_left_primerlen left, $opt_right_primerlen right)",
# 	'outfile'     => $all_stripped,
# 	'savelog'     => "$all_stripped.log",
# });


# # Quality filter
# run({
# 	'command' => qq($dep->{u10}->{binary} -fastq_filter "$all_stripped" -fastq_maxee 1.0 -fastaout "$all_filtered" -relabel Filt),
# 	'description' => "Quality filter",
# 	'outfile'     => $all_filtered,
# 	'savelog'     => "$all_filtered.log",
# });

# # Find unique read sequences and abundances
# run({
# 	'command' => qq($dep->{u10}->{binary}  -fastx_uniques "$all_filtered" -sizeout -relabel Uniq -fastaout "$all_unique"),
# 	'description' => "Find unique read sequences and abundances",
# 	'outfile'     => $all_unique,
# 	'savelog'     => "$all_unique.log",
# });



# # Make 97% OTUs and filter chimeras
# run({
# 	'command' => qq($dep->{u10}->{binary}  -cluster_otus "$all_unique" -otus "$all_otus" -relabel Otu),
# 	'description' => "Make 97% OTUs and filter chimeras",
# 	'outfile'     => "$all_otus",
# 	'savelog'     => "$all_otus.log",
# });


# # Denoise: predict biological sequences and filter chimeras
# run({
# 	'command' => qq($dep->{u10}->{binary}  -unoise3 "$all_unique" -zotus "$all_zotus"),
# 	'description' => "Make 97% OTUs and filter chimeras",
# 	'outfile'     => $all_zotus,
# 	'savelog'     => "$all_zotus.log",
# });

# run({
# 	'command' => qq(sed -i 's/Zotu/OTU/' $all_zotus),
# 	'description' => "Renaming ASV OTUs",
# 	'outfile'     => $all_zotus,

# });





# for my $otus ($all_otus, $all_zotus) {
# 	my $tag = 'OTUs';
# 	$tag = 'ASVs' if ($otus =~/asv/i);

# 	my $otutabraw   = qq("$opt_output_dir"/${tag}_tab.raw);
# 	my $otutab      = qq("$opt_output_dir"/${tag}_tab.txt);
# 	my $alpha       = qq("$opt_output_dir"/${tag}_alpha.txt);
# 	my $tree        = qq("$opt_output_dir"/${tag}.tree);
# 	my $beta_dir    = qq("$opt_output_dir"/${tag}_beta);
# 	my $rarefaction = qq("$opt_output_dir"/${tag}_rarefaction.txt);
# 	my $taxonomy    = qq("$opt_output_dir"/${tag}_taxonomy.txt);
# 	my $genus       = qq("$opt_output_dir"/${tag}_taxonomy_genus.txt);
# 	my $phylum      = qq("$opt_output_dir"/${tag}_taxonomy_phylum.txt);

# 	# Make OTU table
# 	run({
# 		'command' => qq($dep->{u10}->{binary}   -otutab "$all_merged" -otus "$otus" -otutabout "$otutabraw"),
# 		'description' => "Make $tag table",
# 		'outfile'     => $otutabraw,
# 		'savelog'     => "$otutabraw.log",
# 	});


# 	# Normalize to 5k reads / sample
# 	run({
# 		'command' => qq($dep->{u10}->{binary}  -otutab_norm "$otutabraw" -sample_size $opt_sample_size -output "$otutab"),
# 		'description' => "Subsampling to $opt_sample_size",
# 		'outfile'     => $otutab,
# 		'savelog'     => "$otutab.log",
# 	});



# 	# Alpha diversity
# 	run({
# 		'command' => qq($dep->{u10}->{binary}  -alpha_div "$otutab" -output "$alpha"),
# 		'description' => "Alpha diversity",
# 		'outfile'     => $alpha,
# 		'savelog'     => "$alpha.log",
# 	});

# 	# Make OTU tree
# 	run({
# 		'command' => qq($dep->{u10}->{binary}  -cluster_agg "$otus" -treeout "$tree"),
# 		'description' => "Make OTU tree",
# 		'outfile'     => $tree,
# 		'savelog'     => "$tree.log",
# 	});

# 	# Beta diversity

# 	makedir("$beta_dir");
# 	run({
# 		'command' => qq($dep->{u10}->{binary}  -beta_div "$otutab" -tree "$tree" -filename_prefix "$beta_dir/"),
# 		'description' => "Beta diversity for $tag",
# 		'savelog'     => "$beta_dir/log.txt",
# 	});

# 	run({
# 		'command' => qq($dep->{u10}->{binary}  -alpha_div_rare "$otutab" -output "$rarefaction"),
# 		'description' => "Rarefaction",
# 		'savelog'     => "$rarefaction.txt",
# 	});

# 	run({
# 		'command' => qq($dep->{u10}->{binary}   -sintax "$otus" -db "$db" -strand both -tabbedout "$taxonomy" -sintax_cutoff 0.8),
# 		'description' => "Taxonomy annotation",
# 		'savelog'     => "$rarefaction.txt",
# 	});

# 	run({
# 		'command' => qq($dep->{u10}->{binary}    -sintax_summary "$taxonomy" -otutabin "$otutab" -rank g -output "$genus"),
# 		'description' => "Taxonomy annotation: genus-level summary",
# 	});
# 	run({
# 		'command' => qq($dep->{u10}->{binary}    -sintax_summary "$taxonomy" -otutabin "$otutab" -rank p -output "$phylum"),
# 		'description' => "Taxonomy annotation: phylum-level summary",
# 	});
# 	# $usearch
# 	# $usearch -sintax_summary sintax.txt -otutabin otutab.txt -rank p -output phylum_summary.txt

# 	# # Find OTUs that match mock sequences
# 	# $usearch -uparse_ref otus.fa -db ../data/mock_refseqs.fa -strand plus \
#  #  	-uparseout uparse_ref.txt -threads 1
# }

# run({
# 	'command' => qq(gzip  --force "$opt_output_dir"/all*.fast*),
# 	'description' => "Compress intermediate files",
# });

# sub init {
# 	my ($dep_ref) = @_;
# 	my $this_binary = $0;
# 	$script_dir = File::Spec->rel2abs(dirname($0));
# 	deb("Script_dir: $script_dir");
# 	if (! defined $opt_input_dir) {
# 		die "FATAL ERROR: Missing input directory (-i INPUT_DIR) with the FASTQ files\n";
# 	} elsif (! -d "$opt_input_dir") {
# 		die "FATAL ERROR: Input directory (-i INPUT_DIR) not found: <$opt_input_dir>\n";
# 	}


# 	foreach my $key ( keys %{ $dep_ref } ) {
# 		if (-e "$script_dir/tools/${ $dep_ref }{$key}->{binary}") {
# 			${ $dep_ref }{$key}->{binary} = "$script_dir/tools/${ $dep_ref }{$key}->{binary}";
# 		}

# 		my $test_cmd = qq(${ $dep_ref }{$key}->{"test"});
# 		$test_cmd =~s/{binary}/${ $dep_ref }{$key}->{binary}/g;
# 		my $cmd = qq($test_cmd  | grep "${ $dep_ref }{$key}->{"check"}");
# 		my $check = run({
# 			'command' => $cmd,
# 			'description' => qq(Checking dependency: <${ $dep_ref }{$key}->{"binary"}>),
# 			'can_fail'    => 1,
# 			'nocache'     => 1,
# 		});
# 		if ($check->{exitcode} > 0) {
# 		  print STDERR color('red'), "Warning: ", color('reset'), ${ $dep_ref }{$key}->{binary}, ' not found in $PATH, trying local binary', "\n" if ($opt_debug);
#       ${ $dep_ref }{$key}->{binary} = "$script_dir/bin/" . ${ $dep_ref }{$key}->{binary};

# 			my $test_cmd = qq(${ $dep_ref }{$key}->{"test"});
# 			$test_cmd =~s/{binary}/${ $dep_ref }{$key}->{binary}/g;
# 			my $cmd = qq($test_cmd  | grep "${ $dep_ref }{$key}->{"check"}");
# 			run({
#                         'command' => $cmd,
#                         'description' => qq(Checking dependency: <${ $dep_ref }{$key}->{"binary"}>),
#                         'can_fail'    => 0,
#                         'nocache'     => 1,
#                 	});
# 		}


# 	}

# 	return $dep_ref;
# }


# sub crash {
# 	die $_[0];
# }

# sub deb_dump {
# 	my $ref = shift @_;
#   dd $ref;
# 	# if (! $opt_nocolor) {
#   #   		print STDERR color('cyan'), "";
# 	# }
# 	# say STDERR Dumper $ref if ($opt_debug);
# 	# if (! $opt_nocolor) {
# 	# 	print STDERR color('reset'), "";
# 	# }
# }
# sub deb {
# 	my ($message, $color) = @_;
# 	$color = 'cyan' unless ($color);
# 	unless ($opt_nocolor) {
# 		print STDERR color($color), "";
# 	}
# 	say STDERR ":: $message" if ($opt_debug);
# 	unless ($opt_nocolor) {
# 		print STDERR color('reset'), "";
# 	}
# }

# sub ver {
# 	my ($message, $color) = @_;
# 	$color = 'reset' unless ($color);
# 	unless ($opt_nocolor) {
# 		print STDERR color($color), "";
# 	}
# 	say STDERR "$message" if ($opt_debug or $opt_verbose);

# 	unless ($opt_nocolor) {
# 		print STDERR color('reset'), "";
# 	}
# }

# sub count_seqs {
# 	my ($filename, $calculate_n50) = @_;
# 	my $all = '';
# 	$all = ' --all ' if (defined $calculate_n50);

# 	my $output;
# 	if ( ! -e "$filename" ) {
# 		$output->{'success'} = 0;
# 		$output->{'message'} = "Unable to locate file <$filename>";
# 	} else {
# 		#0       1       2       3               4       5       6       7       8       9       10      11      12
# 		#file    format  type    num_seqs        sum_len min_len avg_len max_len
# 		#file    format  type    num_seqs        sum_len min_len avg_len max_len Q1      Q2      Q3      sum_gap N50     Q20(%)  Q30(%)
# 		my $file_stats = run({
# 			command 	=> qq(seqkit stats $all --tabular "$filename" | grep -v 'avg_len'),
# 			description => "Counting sequence number of $filename with 'seqkit'",
# 			can_fail    => 0,
# 			no_messages => 1,
# 		});
# 		$output->{success} = 1;
# 		#$output->{cmd} = $file_stats;
# 		my @fields = split /\s+/, $file_stats->{output};

# 		$output->{format}     = $fields[1];
# 		$output->{seq_number} = $fields[3];
# 		$output->{sum_len}    = $fields[4];
# 		$output->{min_len}    = $fields[5];
# 		$output->{avg_len}    = $fields[6];
# 		$output->{max_len}    = $fields[7];
# 		if (defined $calculate_n50) {
# 			$output->{sum_gap} = $fields[11];
# 			$output->{N50} = $fields[12];
# 		}
# 		return $output;
# 	}
# }


# sub makedir {
#     my $dirname = shift @_;
#     if (-d "$dirname") {
#         if ($opt_rewrite) {
#             run({
#                 command     => qq(rm -rf "$dirname/*"),
#                 description => "Erasing directory (!): $dirname",
#             });
#         }
#         say STDERR "Output directory found: $dirname" if $opt_debug;
#     } else {
#         my $check = run({
#             'command'     => qq(mkdir -p "$dirname"),
#             'can_fail'    => 0,
#             'description' => "Creating directory <$dirname>",
#             'no_messages' => 1,
#         });

#     }
# }


# sub run {
# 	my $run_ref = $_[0];
#     # Expects an object
#     #     S command            the shell command
#     #     S description        fancy description
#     #     S outfile            die if outfile is empty / doesn't exist
#     #     - nocache            dont load pre-calculated files even if found
#     #     - keep_stderr        redirect stderr to stdout (default: to dev null)
#     #     - no_redirect        dont redirect stderr (the command will do)
#     #     S savelog            save STDERR to this file path
#     #     - can_fail           dont die on exit status > 0
#     #     - no_messages        suppress verbose messages: internal command

#     my $start_time = [gettimeofday];
#     my $start_date = localtime->strftime('%m/%d/%Y %H:%M');

#     my %output = ();
#     my $md5 = md5_hex("$run_ref->{command} . $run_ref->{description}");

#     # Check a command was to be run
#     unless ($run_ref->{command}){
#         deb_dump($run_ref);
#         die "No command received $run_ref->{description}\n";
#     } else {
#     	deb("Executing: $run_ref->{command}");
#     }

#     # Caching
#     $run_ref->{md5} = "$opt_output_dir/.$md5";
#     $run_ref->{executed} = $start_date;

#     if (-e  "$run_ref->{md5}"  and ! $opt_force_recalculate and !$run_ref->{nocache} ) {
#         ver(" - Skipping $run_ref->{description}: output found") unless ($run_ref->{no_messages});
#         $run_ref = retrieve("$run_ref->{md5}");
#         $run_ref->{loaded_from_cache} = 1;
#         deb_dump($run_ref);

#         return $run_ref;
#     }
#     $run_ref->{description} = substr($run_ref->{command}, 0, 12) . '...' if (! $run_ref->{description});


#     # Save program output?
#     my $savelog = ' 2> /dev/null ';

#     $savelog = '   ' if ($run_ref->{keep_stderr});
#     $savelog = '' if ($run_ref->{no_redirect});
#     $savelog = qq( > "$run_ref->{savelog}"  ) if (defined $run_ref->{savelog});




#     #        < < <<<<< EXECUTION >>>>>> > >
#     my $output_text = `$run_ref->{command} $savelog`;
#     $run_ref->{output} = $output_text;
#     $run_ref->{exitcode} = $?;

#     # Check status (dont die if {can_fail} is set)
#     if ($?) {
#         deb(" - Execution failed: $?");
#         if (! $run_ref->{can_fail}) {
#         	eval {
#             	say STDERR color('red'), Dumper $run_ref, color('reset');
#             };
#             die " FATAL ERROR:\n Program failed and returned $?.\n Program: $run_ref->{description}\n Command: $run_ref->{command}";
#         } else {
#             ver("Command failed, but it's tolerated [$run_ref->{description}]") unless ($run_ref->{no_messages});
#         }
#     }

#     # Check output file
#     if (defined $run_ref->{outfile}) {
#         die "FATAL ERROR: Output file null ($run_ref->{outfile})" if (-z "$run_ref->{outfile}");
#     }

#     if (defined $run_ref->{count_seqs}) {
#         my $count = count_seqs($run_ref->{count_seqs});
#         $run_ref->{tot_seqs} = $count->{seq_number};
#         $run_ref->{tot_bp}   = $count->{sum_len};
#         $run_ref->{seq_min_len}   = $count->{min_len};
#         $run_ref->{seq_max_len}   = $count->{max_len};
#         $run_ref->{seq_avg_len}   = $count->{avg_len};
#         if (defined $run_ref->{min_seqs} and $count->{seq_number} < $run_ref->{min_seqs}) {
#             deb("Test fails: min sequences ($run_ref->{min_seqs}) not met ($count->{seq_number} in $run_ref->{count_seqs})");
#             die "FATAL ERROR: File <$run_ref->{count_seqs} has only $count->{seq_number} sequences, after executing $run_ref->{description}\n";
#         }
#     }

#     my $elapsed_time = tv_interval ( $start_time, [gettimeofday]);
#     $run_ref->{elapsed} = $elapsed_time;

#     die unless defined $run_ref->{exitcode};

#     if (! defined $run_ref->{nocache}) {
#         deb("Caching result $run_ref->{elapsed}");
#         nstore $run_ref, "$run_ref->{md5}" || die " FATAL ERROR:\n Unable to write log information to '$run_ref->{md5}'.\n";
#     }

#     if ($opt_debug) {
#         deb_dump($run_ref);
#     } elsif ($opt_verbose) {
#         ver(" - $run_ref->{description}") unless ($run_ref->{no_messages});;
#     }
#     ver("    Done ($elapsed_time s)", 'blue') unless ($run_ref->{no_messages});
#     return $run_ref;
# }
