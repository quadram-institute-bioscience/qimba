import click
import os
import importlib
import pkgutil
from collections import defaultdict
from typing import Dict, List, Optional
from . import commands
from .config import load_config

# Define command groups and their descriptions
COMMAND_GROUPS = {
    'sample': {
        'name': 'Sample Management',
#        'description': 'Commands for handling sample information and mapping files',
        'commands': ['make-mapping',
                      'show-samples']
    },
    'sequence': {
        'name': 'Sequence Processing',
#        'description': 'Commands for processing sequence data',
        'commands': [
            'merge',
            'derep']
    },
    'formats': {
        'name': 'Format conversions and manipulation',
#        'description': 'Commands for processing sequence data',
        'commands': ['dada2-split']
    },
    'file': {
        'name': 'File Operations',
#        'description': 'Commands for handling files and formats',
        'commands': ['check-tab']
    },
    'util': {
        'name': 'Utility Commands',
#        'description': 'General utility commands',
        'commands': ['version']
    }
}

class GroupedQimbaCLI(click.MultiCommand):
    def list_commands(self, ctx: click.Context) -> List[str]:
        """List all available commands."""
        commands = []
        command_folder = os.path.join(os.path.dirname(__file__), 'commands')
        
        for _, name, _ in pkgutil.iter_modules([command_folder]):
            if not name.startswith('_'):
                commands.append(name.replace('_', '-'))
        
        commands.sort()
        return commands
    
    def get_command(self, ctx: click.Context, cmd_name: str) -> Optional[click.Command]:
        """Load a command by name."""
        try:
            mod = importlib.import_module(
                f'.commands.{cmd_name.replace("-", "_")}',
                package='qimba'
            )
            return mod.cli
        except ImportError:
            return None
    
    def format_commands(self, ctx: click.Context, formatter: click.HelpFormatter) -> None:
        """Custom command formatter that groups commands."""
        # Get all commands
        commands = self.list_commands(ctx)
        
        # Create groups including "Other" for ungrouped commands
        groups: Dict[str, List[tuple]] = defaultdict(list)
        
        # Sort commands into groups
        for cmd_name in commands:
            cmd = self.get_command(ctx, cmd_name)
            if cmd is None:
                continue
            
            help_str = cmd.get_short_help_str()
            
            # Find which group this command belongs to
            group_found = False
            for group_info in COMMAND_GROUPS.values():
                if cmd_name in group_info['commands']:
                    groups[group_info['name']].append((cmd_name, help_str))
                    group_found = True
                    break
            
            # If command isn't in any group, add to Other Commands
            if not group_found:
                groups['Other Commands'].append((cmd_name, help_str))
        
        # Get longest command name for padding
        limit = formatter.width - 6
        
        # Write groups in defined order, followed by Other Commands
        for group_id, group_info in COMMAND_GROUPS.items():
            group_name = group_info['name']
            if groups[group_name]:
                with formatter.section(group_name):
                    if 'description' in group_info:
                        formatter.write_text(group_info['description'])
                    formatter.write_dl(groups[group_name])
        
        # Write ungrouped commands last if there are any
        if groups['Other Commands']:
            with formatter.section('Other Commands'):
                formatter.write_text('Additional commands not in main categories')
                formatter.write_dl(groups['Other Commands'])

@click.command(cls=GroupedQimbaCLI)
@click.option('--config', type=click.Path(), help='Path to config file')
def main(config):
    """Qimba - Bioinformatics Toolkit
    
    A modular toolkit for bioinformatics analysis with focus on amplicon processing.
    """
    # Load configuration
    ctx = click.get_current_context()
    ctx.obj = {'config': load_config(config)}

if __name__ == '__main__':
    main()
