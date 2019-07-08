#!/bin/bash

IN=$1
OUT="$(echo $1 | cut -f1 -d. )"
set -euxo pipefail
usearch_10  -cluster_otus "$IN" -minsize 3 -otus "$OUT.otus.fasta" -relabel OTU -uparseout "$OUT.otus.txt"
usearch_10  -unoise3 "$IN"  -zotus "$OUT.asv.fasta"
