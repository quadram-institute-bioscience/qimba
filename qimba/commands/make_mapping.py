# qimba/commands/make_mapping.py
import click
from pathlib import Path
import sys
from typing import Dict, List, Tuple, Optional, TextIO
from collections import defaultdict
import csv
import re

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
            pattern_opts = [(x,y) for x,y in opts if x in ['-e', '--ext', '-1', '--tag-for', 
                                                         '-2', '--tag-rev', '-s', '--strip']]
            other_opts = [(x,y) for x,y in opts if (x,y) not in main_opts and (x,y) not in pattern_opts]

            if main_opts:
                with formatter.section('Output Options'):
                    formatter.write_dl(main_opts)
            if pattern_opts:
                with formatter.section('File Pattern Options'):
                    formatter.write_dl(pattern_opts)
            if other_opts:
                with formatter.section('Other Options'):
                    formatter.write_dl(other_opts)

def process_filename(filename: Path, extension: str, strip_str: str, 
                    tag_for: str, tag_rev: str) -> Tuple[Optional[str], bool]:
    """
    Process a filename to extract sample name and determine if it's forward/reverse.
    
    Returns:
        Tuple of (sample_name, is_forward)
        sample_name will be None if filename doesn't match pattern
    """
    # Check extension
    if not str(filename).endswith(extension):
        return None, False
        
    # Remove extension
    name = str(filename.name)[:-len(extension)]
    
    # Strip additional pattern if specified
    if strip_str:
        name = name.replace(strip_str, '')
    
    # Check for forward/reverse tags
    if tag_for in name:
        return name.split(tag_for)[0], True
    elif tag_rev in name:
        return name.split(tag_rev)[0], False
    
    return None, False

def write_mapping(samples: Dict[str, Dict[str, Path]], 
                 output: TextIO,
                 input_dir: Path) -> None:
    """Write the mapping file in TSV format."""
    writer = csv.writer(output, delimiter='\t', lineterminator='\n')
    
    # Write header
    writer.writerow(['Sample ID', 'Forward', 'Reverse'])
    
    # Write samples
    for sample_id, files in sorted(samples.items()):
        forward = files.get('forward', '')
        reverse = files.get('reverse', '')
        
        # Use relative paths from input directory
        if forward:
            forward = str(Path(forward).relative_to(input_dir))
        if reverse:
            reverse = str(Path(reverse).relative_to(input_dir))
            
        writer.writerow([sample_id, forward, reverse])

@click.command(cls=GroupedCommand)
@click.argument('input-dir', type=click.Path(exists=True, file_okay=False))
@click.option('-o', '--output', type=click.Path(dir_okay=False),
              help='Output mapping file (default: stdout)')
@click.option('-e', '--ext', default='.fastq.gz',
              help='File extension to look for [default: .fastq.gz]')
@click.option('-1', '--tag-for', default='_R1',
              help='Forward read tag [default: _R1]')
@click.option('-2', '--tag-rev', default='_R2',
              help='Reverse read tag [default: _R2]')
@click.option('-s', '--strip', default='',
              help='Additional string to strip from filenames')
def cli(input_dir, output, ext, tag_for, tag_rev, strip):
    """Generate a sample mapping file from a directory of sequence files.
    
    \b
    This command scans INPUT_DIR for sequence files and creates a mapping file
    based on the file naming pattern. Sample names are extracted by:
    1. Removing the extension
    2. Stripping any additional pattern (--strip)
    3. Splitting on forward/reverse tags and taking the prefix
    
    Each sample must have an R1 file, R2 is optional.
    
    Example usage:
      qimba make-mapping data_dir -o mapping.tsv
      qimba make-mapping data_dir -e .fq.gz -1 _1 -2 _2 -s _filtered
    """
    input_path = Path(input_dir)
    samples = defaultdict(dict)
    errors = []
    
    # Scan directory
    for filepath in input_path.glob('**/*'):
        if not filepath.is_file():
            continue
            
        sample_id, is_forward = process_filename(
            filepath, ext, strip, tag_for, tag_rev
        )
        
        if sample_id:
            file_type = 'forward' if is_forward else 'reverse'
            
            # Check for duplicate files
            if file_type in samples[sample_id]:
                errors.append(
                    f"Duplicate {file_type} file found for sample {sample_id}:\n"
                    f"  Existing: {samples[sample_id][file_type]}\n"
                    f"  New: {filepath}"
                )
            else:
                samples[sample_id][file_type] = filepath
    
    # Validate samples
    for sample_id, files in samples.items():
        if 'forward' not in files:
            errors.append(f"Sample {sample_id} missing forward read file")
    
    # Report errors if any
    if errors:
        click.echo("Errors found:", err=True)
        for error in errors:
            click.echo(f"  {error}", err=True)
        sys.exit(1)
    
    if not samples:
        click.echo(
            f"No valid samples found in {input_dir} "
            f"(extension: {ext}, forward: {tag_for}, reverse: {tag_rev})",
            err=True
        )
        sys.exit(1)
    
    # Write output
    try:
        if output:
            with open(output, 'w') as f:
                write_mapping(samples, f, input_path)
            click.echo(f"Created mapping file: {output}")
        else:
            write_mapping(samples, sys.stdout, input_path)
            
    except IOError as e:
        click.echo(f"Error writing mapping file: {e}", err=True)
        sys.exit(1)
