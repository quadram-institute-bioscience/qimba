import click
from ..core import Mapping

@click.command()
@click.argument('mapping_file', type=click.Path(exists=True))
@click.option('--attr', help='Show specific attribute for all samples')
def cli(mapping_file, attr):
    """Display sample information from a mapping file."""
    try:
        mapping = Mapping(mapping_file)
        
        click.echo(f"\nFound {len(mapping)} samples")
        click.echo(f"Available attributes: {', '.join(mapping.columns)}\n")
        
        if attr:
            # Show specific attribute for all samples
            click.echo(f"Values for attribute '{attr}':")
            for sample_id in mapping:
                value = mapping.get_sample_attr(sample_id, attr)
                click.echo(f"{sample_id}: {value}")
        else:
            # Show all info for each sample
            for sample_id in mapping:
                click.echo(f"\nSample: {sample_id}")
                for col in mapping.columns:
                    if col != 'Sample ID':  # Skip ID since we just showed it
                        value = mapping.get_sample_attr(sample_id, col)
                        click.echo(f"  {col}: {value}")
    
    except (ValueError, KeyError) as e:
        click.echo(f"Error: {str(e)}", err=True)
        click.get_current_context().exit(1)
