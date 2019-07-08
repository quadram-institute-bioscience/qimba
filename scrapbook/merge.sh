#!/bin/bash

V=vsearch
THREADS=4
MIN_OVERLAP=40
MAX_EE=2

MIN_LEN=300
MAX_LEN=500
STRIP_LEFT=18
STRIP_RIGHT=18

if [[ "NO$1" == "NO" ]];
then
	echo "Provide the R1 filename (R2 will be auto calculated)"
	exit 1
fi

R1=$1
R2=${R1/_R1/_R2}
OUT="$(echo "$R1" | cut -f 1 -d .)"

echo "$R1"
echo "$R2"
echo "=$OUT"
if [[ $R1 == $R2 ]];
then
	echo "Unable to autodetect R2 (_R1 not found in $R1?)"
	exit 1
fi

$V --threads $THREADS --no_progress \
	--fastq_mergepairs "$R1" --reverse "$R2" \
	--fastq_minovlen $MIN_OVERLAP \
        --fastq_maxdiffs 45 \
        --fastqout "$OUT.join.fq" \
        --fastq_eeout --fastq_maxee $MAX_EE

$V  --threads $THREADS --no_progress \
        --fastq_filter "$OUT.join.fq" \
        --fastq_maxee 0.9 \
        --fastq_minlen $MIN_LEN \
        --fastq_maxlen $MAX_LEN \
        --fastq_maxns 0 \
        --fastq_stripleft  $STRIP_LEFT \
        --fastq_stripright $STRIP_RIGHT \
        --fastaout "$OUT.fasta" \
        --fasta_width 0

$V --threads $THREADS --no_progress \
        --derep_fulllength "$OUT.fasta" \
        --strand plus \
        --output "$OUT.derep.fasta" \
        --sizeout \
        --uc "$OUT.derep.uc" \
        --relabel $(basename "$OUT" | cut -f1 -d_). \
        --fasta_width 0
