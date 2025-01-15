import click
import csv
from pathlib import Path
from typing import Tuple, Dict

def check_tsv(filename: str, strict: bool = False) -> Tuple[int, int, Dict[int, int]]:
    """
    Check a TSV file and return its dimensions and column count distribution.
    
    Args:
        filename: Path to TSV file
        strict: If True, raises error on inconsistent column counts
        
    Returns:
        Tuple of (rows, columns, column_distribution)
        where column_distribution is a dict of column_count: number_of_rows
    """
    rows = 0
    columns = 0
    column_counts = {}
    
    with open(filename, 'r') as f:
        tsv_reader = csv.reader(f, delimiter='\t')
        
        for row_num, row in enumerate(tsv_reader, 1):
            col_count = len(row)
            
            # Update column count distribution
            column_counts[col_count] = column_counts.get(col_count, 0) + 1
            
            # Set initial column count
            if rows == 0:
                columns = col_count
            # Check for consistency in strict mode
            elif strict and col_count != columns:
                raise ValueError(
                    f"Inconsistent column count at row {row_num}: "
                    f"expected {columns}, got {col_count}"
                )
            
            rows += 1
            
    return rows, columns, column_counts

@click.command()
@click.argument('files', nargs=-1, type=click.Path(exists=True))
@click.option('--strict/--no-strict', default=None,
              help='Strictly enforce consistent column counts')
def cli(files, strict):
    """Check TSV files for their dimensions and consistency."""
    # Get configuration
    ctx = click.get_current_context()
    config = ctx.obj['config']
    
    # If strict not specified in command line, check config
    if strict is None:
        strict = config.getboolean('check-tab', 'strict', fallback=False)
    
    # Process each file
    for file in files:
        path = Path(file)
        click.echo(f"\nAnalyzing {path.name}:")
        
        try:
            rows, columns, col_dist = check_tsv(file, strict)
            
            # Print summary
            click.echo(f"Total rows: {rows}")
            
            if len(col_dist) == 1:
                click.echo(f"Columns: {columns} (consistent)")
            else:
                click.echo("Column count distribution:")
                for col_count, count in sorted(col_dist.items()):
                    percentage = (count / rows) * 100
                    click.echo(f"  {col_count} columns: {count} rows ({percentage:.1f}%)")
                
        except ValueError as e:
            click.echo(f"Error: {str(e)}", err=True)
            if strict:
                ctx.exit(1)
        except Exception as e:
            click.echo(f"Error processing {path.name}: {str(e)}", err=True)
            ctx.exit(1)
