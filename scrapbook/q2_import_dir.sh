#!/bin/bash
set -euo pipefail

function abspath() {
    # generate absolute path from relative path
    # $1     : relative filename
    # return : absolute path
    if [ -d "$1" ]; then
        # dir
        (cd "$1"; pwd)
    elif [ -f "$1" ]; then
        # file
        if [[ $1 = /* ]]; then
            echo "$1"
        elif [[ $1 == */* ]]; then
            echo "$(cd "${1%/*}"; pwd)/${1##*/}"
        else
            echo "$(pwd)/$1"
        fi
    fi
}

OUTPUT='qiime2'
THREADS=4
VERBOSE=0
PHRED=33
NODADA=0;

LIB='Single';
PAIRED='';

# Dada2
MAX_EE=2.0;
TRIM_LEFT=8;
TRUNC_LEN_1=0;
TRUNC_LEN_2=0;

# Test flash parameters
Test_Flash_Min=30;
Test_Flash_Max=300;

echo "USAGE:
  import_directory.sh [options] [-o OUTPUT] -i directory 

  -n      nodada2, import only
  -m      metadata file
  -f      trunc len (R1)
  -r      trunc len (R2)
  -j      Import Phred64 instead of Phred33
  -v      Verbose
";

while getopts f:r:t:n:o:i:vj option
do
        case "${option}"
                in
              		f) TRUNC_LEN_1=${OPTARG};;
                  r) TRUNC_LEN_2=${OPTARG};;
                  t) THREADS=${OPTARG};;
                  n) NODADA=1;;
                  o) OUTPUT=${OPTARG};;
                  i) INPUT_DIR=${OPTARG};;
                  v) VERBOSE=1;;
                  j) PHRED=33;;
                  m) METADATA=${OPTARG};;
                  ?) echo " Wrong parameter $OPTARG";;
         esac
done
shift "$(($OPTIND -1))"

if [ -z ${INPUT_DIR+x} ]; then
	echo " ERROR: Missing input directory (-i INPUT_DIR)"
	exit;
fi

INPUT_DIR=$(abspath "$INPUT_DIR");


mkdir -p "$OUTPUT"
MANIFEST="$OUTPUT/import.manifest"



if [ $VERBOSE -eq 1 ]; then
	echo "
	Input dir: $INPUT_DIR
	Manifest:  $MANIFEST
	OutputDir: $OUTPUT/
	Format:    Phred$PHRED
	";
fi


echo " - Manifest generation"
echo "sample-id,absolute-filepath,direction" > $MANIFEST

for FASTQ_FILE in $(find $INPUT_DIR -type f ! -size 0 | sort);
do
	if [[ $FASTQ_FILE =~ '_R1' ]]; then
		STRAND='forward'
	elif [[ $FASTQ_FILE =~ '_R2' ]]; then

	    LIB='Paired'
		PAIRED='PairedEnd'

		STRAND='reverse'
	else
		echo " ERROR: File '$FASTQ_FILE' not strand tagged (_R1 or _R2)"
		exit;
	fi
	NAME=$(basename $FASTQ_FILE | cut -f1 -d_);
        echo "$NAME,$FASTQ_FILE,$STRAND" >> $MANIFEST
	if [ $VERBOSE -eq 1 ]; then
		echo "Adding $FASTQ_FILE ($NAME, $STRAND)"
	fi
done

echo " - Reads statistics"
seqkit stats -j $THREADS -T $(find $INPUT_DIR -type f ! -size 0 | grep R1 | sort) > "$OUTPUT/stats_R1.txt";
TEST_R1=$(find $INPUT_DIR -type f ! -size 0 | sort | grep R1 | head -n 1);
TEST_R2=${TEST_R1/_R1/_R2};

if  [ $LIB == 'Paired' ]; then
	seqkit stats -j $THREADS -T $(find $INPUT_DIR -type f ! -size 0 | grep R2 | sort) > "$OUTPUT/stats_R2.txt";
	flash -m $Test_Flash_Min -M $Test_Flash_Max -o "$OUTPUT/s1" $TEST_R1 $TEST_R2 >/dev/null 2>&1
fi



if [ -e "$OUTPUT/$LIB.qza" ]; then
	echo " - SKIPPING Import: $LIB.qza found"
else

	echo " - Importing $LIB"
	qiime tools import \
	    --type SampleData[${PAIRED}SequencesWithQuality] \
	    --input-path $MANIFEST \
	    --output-path "$OUTPUT/$LIB.qza" \
	    --input-format  ${LIB}EndFastqManifestPhred$PHRED
fi

#WAS    --source-format ${LIB}EndFastqManifestPhred$PHRED
 

if [ $NODADA -eq 1 ];
then
	echo "Imported reads, skipping Dada2"
	exit;
fi



if [ "$LIB" == 'Paired' ];
then
	echo " - Denoising $LIB"
	qiime dada2 denoise-paired \
          --i-demultiplexed-seqs "$OUTPUT/$LIB.qza" \
          --p-trim-left-f $TRIM_LEFT \
          --p-trim-left-r $TRIM_LEFT \
          --p-trunc-len-f $TRUNC_LEN_1 \
          --p-trunc-len-r $TRUNC_LEN_2 \
          --p-n-threads  $THREADS \
          --p-max-ee $MAX_EE \
          --o-representative-sequences "$OUTPUT/rep-seqs.qza" \
          --o-table "$OUTPUT/table.qza" \
          --o-denoising-stats "$OUTPUT/stats.qza"
else
	echo " - Denoising $LIB"
	qiime dada2 denoise-single \
          --i-demultiplexed-seqs "$OUTPUT/$LIB.qza" \
          --p-trim-left $TRIM_LEFT \
          --p-trunc-len $TRUNC_LEN_1 \
          --p-n-threads  $THREADS \
          --p-max-ee $MAX_EE \
          --o-representative-sequences "$OUTPUT/rep-seqs.qza" \
          --o-table "$OUTPUT/table.qza" \
          --o-denoising-stats "$OUTPUT/stats.qza"
fi
fi

if [[ -e "$METADATA" ]];
then
  qiime feature-table summarize \
    --i-table "$OUTPUT/table.qza" \
    --o-visualization "$OUTPUT/table.qzv" \
    --m-sample-metadata-file "$METADATA"
  qiime feature-table tabulate-seqs \
    --i-data "$OUTPUT/rep-seqs.qza" \
    --o-visualization "$OUTPUT/rep-seqs.qzv"
fi
