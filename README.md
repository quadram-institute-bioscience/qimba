# Quadram Institute MetaBarcoding Analysis

![Qimba Logo](./assets/qimba-header.svg)

A modular bioinformatics toolkit designed to facilitate metabarcoding analyses, with a focus on amplicon processing and sequence data management.

## Introduction

Qimba provides a collection of commands for handling common tasks in metabarcoding workflows, including:

- Sequence processing and quality control
- Format conversions


## Qimba CLI

Commands are organized into functional groups (run `qimba --help` to list them all):

### Sample Management
- `make-mapping`: Generate sample sheets from sequence files
- `show-samples`: Display sample information from mapping files

### Sequence Processing
- `merge`: Merge paired-end reads
- `derep`: Dereplicate sequences while preserving abundance information

### Format Conversions
- `dada2-split`: Convert DADA2 output format to FASTA and simplified TSV

### File Operations
- `check-tab`: Validate TSV file structure

### Utility Commands
- `version`: Display Qimba version information

Example usage:
```bash
# Create a sample sheet from a directory of fastq files
qimba make-mapping data_dir -o mapping.tsv

# Merge paired-end reads
qimba merge -i mapping.tsv -o merged.fastq --threads 8

# Dereplicate sequences
qimba derep -i merged.fasta -o unique.fasta
```

## Configuration

Qimba uses a configuration file located at `~/.config/qimba.ini`. Default settings:

```ini
[qimba]
default_output_dir = .
threads = 4
```

Override configuration using command-line options or by specifying a custom config file:
```bash
qimba --config my_config.ini [command]
```

## Contributing

We welcome contributions! Please check our **[Developer Documentation](https://github.com/quadram-institute-bioscience/qimba/wiki)** for information about:
- Code structure
- Adding new commands
- Testing guidelines
- Best practices

See [https://www.contributor-covenant.org/](Contributor covenant)

## Authors

Qimba is developed and maintained by [Quadram Institute Bioscience - Core Bioinformatics](https://quadram-institute-bioscience.github.io/).

## License

MIT
