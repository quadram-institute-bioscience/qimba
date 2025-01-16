import click
from pathlib import Path
import sys
import re
from typing import Optional, Tuple, Dict
from ..formats import SampleSheet

class GroupedCommand(click.Command):
    def format_options(self, ctx, formatter):
        """Writes all the options into the formatter if they exist."""
        opts = []
        for param in self.get_params(ctx):
            rv = param.get_help_record(ctx)
            if rv is not None:
                opts.append(rv)

        if opts:
            main_opts = [(x,y) for x,y in opts if x.startswith('-o') or x.startswith('-a')]
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


def rename_sample_id(sample_id: str, safe_char: str, prefix: str = "Sample",
                    name_counts: dict = None) -> str:
    """
    Rename a sample ID according to specified rules.
    
    Args:
        sample_id: Original sample ID
        safe_char: Character to replace non-alphanumeric characters with
        prefix: Prefix to add for samples starting with digits
        name_counts: Dictionary to track name occurrences for handling duplicates
    
    Returns:
        Renamed sample ID
    """
    if name_counts is None:
        name_counts = {}
        
    new_name = sample_id
    
    # Rule 1: Prepend prefix if starts with digit
    if new_name[0].isdigit():
        new_name = prefix + safe_char + new_name
        
    # Rule 2: Replace non-alphanumeric chars with safe_char
    new_name = re.sub(r'[^a-zA-Z0-9]', safe_char, new_name)
    
    # Rule 3: Handle duplicates
    base_name = new_name
    if base_name in name_counts:
        name_counts[base_name] += 1
        new_name = f"{base_name}{name_counts[base_name]}"
    else:
        name_counts[base_name] = 0
        
    return new_name


def collect_read_files(input_path: Path, ext: str, strip_str: str, 
                      tag_for: str, tag_rev: str) -> Dict[str, Dict[str, Path]]:
    """
    Scan directory and collect read files, pairing R1 and R2 files by sample name.
    
    Returns:
        Dictionary mapping sample IDs to their forward and reverse read files
    """
    # Dictionary to store file pairs: sample_id -> {'forward': path, 'reverse': path}
    read_pairs = {}
    
    # First pass: collect all files and their types
    for filepath in input_path.glob('**/*'):
        if not filepath.is_file():
            continue
            
        sample_id, is_forward = process_filename(filepath, ext, strip_str, tag_for, tag_rev)
        
        if not sample_id:
            continue
            
        # Initialize or update sample entry
        if sample_id not in read_pairs:
            read_pairs[sample_id] = {'forward': None, 'reverse': None}
            
        file_type = 'forward' if is_forward else 'reverse'
        
        # Check for duplicate files
        if read_pairs[sample_id][file_type] is not None:
            raise ValueError(
                f"Duplicate {file_type} file found for sample {sample_id}:\n"
                f"  Existing: {read_pairs[sample_id][file_type]}\n"
                f"  New: {filepath}"
            )
            
        read_pairs[sample_id][file_type] = filepath
        
    return read_pairs


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
@click.option('-c', '--safe-char', default='_',
              help='Safe character for sample names (default _)')
@click.option('-a', '--absolute', is_flag=True,
              help='Use absolute paths in output')
@click.option('-k', '--dont-rename', is_flag=True,
              help='Do not remove illegal chars from SampleIDs')
def cli(input_dir: str, output: str, ext: str, tag_for: str, tag_rev: str, 
        strip: str, safe_char: str, absolute: bool, dont_rename: bool):
    """Generate a sample mapping file from a directory of sequence files.
    
    This command scans INPUT_DIR for sequence files and creates a mapping file
    based on the file naming pattern. Sample names are extracted by:
    1. Removing the extension
    2. Stripping any additional pattern (--strip)
    3. Splitting on forward/reverse tags and taking the prefix
    
    Each sample must have an R1 file, R2 is optional.
    """
    input_path = Path(input_dir)
    errors = []
    name_counts = {}  # For tracking duplicate renamed samples
    
    try:
        # Collect and pair read files
        read_pairs = collect_read_files(input_path, ext, strip, tag_for, tag_rev)
        
        # Create sample sheet
        sample_sheet = SampleSheet()
        
        # Process each sample
        for sample_id, files in read_pairs.items():
            # Skip samples without forward reads
            if not files['forward']:
                errors.append(f"Sample {sample_id} missing forward read file")
                continue
                
            # Rename sample if needed
            final_id = (rename_sample_id(sample_id, safe_char, name_counts=name_counts) 
                       if not dont_rename else sample_id)
                
            # Add to sample sheet
            try:
                sample_sheet.add_sample(
                    final_id,
                    files['forward'].absolute() if absolute else files['forward'],
                    files['reverse'].absolute() if absolute and files['reverse'] else files['reverse']
                )
            except ValueError as e:
                errors.append(str(e))
        
        # Check if any samples were found
        if len(sample_sheet) == 0:
            click.echo(
                f"No valid samples found in {input_dir} "
                f"(extension: {ext}, forward: {tag_for}, reverse: {tag_rev})",
                err=True
            )
            sys.exit(1)
            
        # Report errors if any were found
        if errors:
            click.echo("Errors found:", err=True)
            for error in errors:
                click.echo(f"  {error}", err=True)
            sys.exit(1)
        
        sample_sheet = sample_sheet.sort()
        # Write output
        if output:
            sample_sheet.save_to_file(output, absolute)
            click.echo(f"Created mapping file: {output}")
        else:
            print(str(sample_sheet))
            
    except (ValueError, IOError) as e:
        click.echo(f"Error processing files: {e}", err=True)
        sys.exit(1)


if __name__ == '__main__':
    cli()