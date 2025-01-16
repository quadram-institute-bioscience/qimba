# Quadram Institute MetaBarcoding Analysis

![Qimba Logo](./assets/qimba-header.svg)

A toolkit to support Metabarcoding Analysis

Qimba comes with a set of subcommands, that you can list running `qimba`:

```text
Usage: qimba [OPTIONS] COMMAND [ARGS]...

  Qimba - Bioinformatics Toolkit

  A modular toolkit for bioinformatics analysis with focus on amplicon
  processing.

Options:
  --config PATH  Path to config file
  --help         Show this message and exit.

Sample Management:
  make-mapping  Generate a sample mapping file from a...
  show-samples  Display sample information from a mapping...

Sequence Processing:
  derep  Dereplicate FASTA sequences using USEARCH.

Format conversions and manipulation:
  dada2-split  Split DADA2 TSV file into FASTA and...

File Operations:
  check-tab  Check TSV files for their dimensions and...

Utility Commands:
  version  Print the version of Qimba.
```

## Configuration file

Some defaults can be set in your `~/.config/qimba.ini` file:


Example configuration:
```ini
[qimba]
default_output_dir = .
threads = 4

[subcommand name]
database = /path/to/database
```
