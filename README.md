# Quadram Institute MetaBarcoding Analysis

A pipeline to analyze 16S using Qiime 2 (2019.4) and USEARCH/VSEARCH.

### Requirements

 * Qiime2 2019.4 should be available in the `$PATH`
 * VSEARCH 2.8 (the binary `vsearch`)
 * Download USEARCH v.10 an place the binary, named `usearch_10`, in the _tools_ subdirectory or in `$PATH`.

Perl modules:
  * IPC::RunExternal
	* FASTX::Reader
	* File::Spec::Functions
	* Archive::Zip
	* Archive::Zip::MemberRead
  * ScriptHelper and QimbaHelper are provided with this repository


### Synopsis
```
./qimba.pl -i reads/ -m mapping_file.tsv -o qimba_output --verbose --debug
```
