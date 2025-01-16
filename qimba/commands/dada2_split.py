# qimba/commands/dada2_split.py
import click
from pathlib import Path
import sys
from typing import List, Dict, TextIO, Tuple
import csv

class GroupedCommand(click.Command):
    def format_options(self, ctx, formatter):
        """Writes all the options into the formatter if they exist."""
        opts = []
        for param in self.get_params(ctx):
            rv = param.get_help_record(ctx)
            if rv is not None:
                opts.append(rv)

        if opts:
            main_opts = [(x,y) for x,y in opts if x.startswith('-o')]
            other_opts = [(x,y) for x,y in opts if not x.startswith('-o')]

            if main_opts:
                with formatter.section('Output Options'):
                    formatter.write_dl(main_opts)
            if other_opts:
                with formatter.section('Other Options'):
                    formatter.write_dl(other_opts)

def validate_tsv(input_file: Path) -> Tuple[List[str], List[str]]:
    """
    Validate the DADA2 TSV format and return headers and sequences.
    
    Returns:
        Tuple of (headers, sequences)
    
    Raises:
        click.BadParameter: If file format is invalid
    """
    try:
        with input_file.open() as f:
            reader = csv.reader(f, delimiter='\t')
            
            # Read and validate header
            try:
                headers = next(reader)
            except StopIteration:
                raise click.BadParameter("Input file is empty")
                
            if len(headers) < 2:
                raise click.BadParameter(
                    "Invalid DADA2 format: TSV must have at least 2 columns "
                    "(sequence and at least one sample)"
                )
                
            # Validate data rows and collect sequences
            sequences = []
            line_num = 1
            for row in reader:
                line_num += 1
                if not row:
                    continue
                    
                if len(row) != len(headers):
                    raise click.BadParameter(
                        f"Invalid DADA2 format: Line {line_num} has {len(row)} "
                        f"fields, expected {len(headers)}"
                    )
                
                # Validate sequence (first column)
                sequence = row[0]
                if not sequence or not all(c in 'ACGTN' for c in sequence.upper()):
                    raise click.BadParameter(
                        f"Invalid sequence at line {line_num}: {sequence[:50]}..."
                    )
                    
                # Validate counts (remaining columns)
                for i, count in enumerate(row[1:], 1):
                    if count and not count.isdigit():
                        raise click.BadParameter(
                            f"Invalid count '{count}' in column {headers[i]} "
                            f"at line {line_num}"
                        )
                
                sequences.append(sequence)
            
            if not sequences:
                raise click.BadParameter("No valid sequences found in input file")
                
            return headers, sequences
            
    except (OSError, UnicodeDecodeError) as e:
        raise click.BadParameter(f"Error reading input file: {e}")

def write_fasta(sequences: List[str], counts: Dict[str, int], output_file: Path) -> None:
    """Write sequences to FASTA format with ASV IDs."""
    try:
        with output_file.open('w') as f:
            for idx, seq in enumerate(sequences, 1):
                f.write(f">ASV{idx} counts={counts[seq]}\n")
                f.write(f"{seq}\n")
    except OSError as e:
        raise click.ClickException(f"Error writing FASTA file: {e}")

def write_tsv(headers: List[str], data: List[List[str]], output_file: Path) -> None:
    """Write simplified TSV with ASV IDs replacing sequences."""
    try:
        with output_file.open('w') as f:
            writer = csv.writer(f, delimiter='\t', lineterminator='\n')
            writer.writerow(headers)
            writer.writerows(data)
    except OSError as e:
        raise click.ClickException(f"Error writing TSV file: {e}")

@click.command(cls=GroupedCommand)
@click.argument('input-file', type=click.Path(exists=True, dir_okay=False))
@click.option('-o', '--output', required=True,
              help='Output basename (without extension)')
@click.option('-v', '--verbose', is_flag=True,
              help='Print detailed progress information')
def cli(input_file: str, output: str, verbose: bool) -> None:
    """Split DADA2 TSV file into FASTA and simplified TSV.

    This command processes a DADA2-format TSV file containing sequences and their
    counts across samples. It generates:
    
    1. A FASTA file containing unique sequences with ASV IDs
    2. A simplified TSV file with ASV IDs replacing sequences
    
    The input TSV must have sequences in the first column and sample counts in
    subsequent columns. Empty counts are treated as zeros.
    
    Example usage:
      qimba dada2-split input.tsv -o output
      qimba dada2-split input.tsv -o output --verbose
    """
    input_path = Path(input_file)
    
    if verbose:
        click.echo(f"Processing {input_path}...")
    
    # Validate input and get headers/sequences
    headers, sequences = validate_tsv(input_path)
    
    if verbose:
        click.echo(f"Found {len(sequences)} unique sequences across {len(headers)-1} samples")
    
    # Process input file
    try:
        with input_path.open() as f:
            reader = csv.reader(f, delimiter='\t')
            next(reader)  # Skip header
            
            # Calculate total counts per sequence
            seq_counts = {}
            simplified_rows = []
            
            for idx, row in enumerate(reader, 1):
                if not row:
                    continue
                    
                sequence = row[0]
                counts = [int(count) if count else 0 for count in row[1:]]
                seq_counts[sequence] = sum(counts)
                
                # Replace sequence with ASV ID
                simplified_rows.append([f"ASV{idx}"] + row[1:])
                
                if verbose and idx % 1000 == 0:
                    click.echo(f"Processed {idx} sequences...")
    
    except (OSError, ValueError) as e:
        raise click.ClickException(f"Error processing input file: {e}")
    
    # Write output files
    output_base = Path(output)
    fasta_path = output_base.with_suffix('.fasta')
    tsv_path = output_base.with_suffix('.tsv')
    
    if verbose:
        click.echo(f"Writing FASTA output to {fasta_path}...")
    write_fasta(sequences, seq_counts, fasta_path)
    
    if verbose:
        click.echo(f"Writing TSV output to {tsv_path}...")
    write_tsv(headers, simplified_rows, tsv_path)
    
    if verbose:
        click.echo("Processing complete!")