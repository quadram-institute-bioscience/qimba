import click
import os
import importlib
import pkgutil
from . import commands
from .config import load_config

class QimbaCLI(click.MultiCommand):
    def list_commands(self, ctx):
        """Dynamically list all available commands."""
        command_folder = os.path.join(os.path.dirname(__file__), 'commands')
        commands = []
        
        for _, name, _ in pkgutil.iter_modules([command_folder]):
            if not name.startswith('_'):
                commands.append(name.replace('_', '-'))
                
        commands.sort()
        return commands
    
    def get_command(self, ctx, cmd_name):
        """Dynamically import the corresponding command module."""
        try:
            mod = importlib.import_module(
                f'.commands.{cmd_name.replace("-", "_")}',
                package='qimba'
            )
            return mod.cli
        except ImportError:
            return None

@click.command(cls=QimbaCLI)
@click.option('--config', type=click.Path(), help='Path to config file')
def main(config):
    """Qimba - Bioinformatics Toolkit"""
    # Load configuration
    ctx = click.get_current_context()
    ctx.obj = {'config': load_config(config)}

