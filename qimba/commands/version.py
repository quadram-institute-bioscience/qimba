import click
from .. import __version__

@click.command()
def cli():
    """Print the version of Qimba."""
    click.echo(f"Qimba version {__version__}")
