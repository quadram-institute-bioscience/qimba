# qimba/commands/derep.py
import click
from pathlib import Path
import sys
import subprocess
from ..core import Job

class ThreadOption(click.Option):
    def get_help_record(self, ctx):
        """Customize the help text to include the config default."""
        if ctx.obj is None or 'config' not in ctx.obj:
            help_text = 'Number of threads (overrides config value)'
        else:
            config = ctx.obj['config']
            default = config.get('qimba', 'threads', fallback='1')
            help_text = f'Number of threads [default from config: {default}]'
            
        self.help = help_text
        return super().get_help_record(ctx)

class GroupedCommand(click.Command):
    def format_options(self, ctx, formatter):
        """Writes all the options into the formatter if they exist."""
        opts = []
        for param in self.get_params(ctx):
            rv = param.get_help_record(ctx)
            if rv is not None:
                opts.append(rv)

        if opts:
            # Split options into groups
            main_opts = [(x,y) for x,y in opts if x.startswith('-i') or x.startswith('-o')]
            runtime_opts = [(x,y) for x,y in opts if x.startswith('--threads') or x.startswith('--verbose')]
            other_opts = [(x,y) for x,y in opts if (x,y) not in main_opts and (x,y) not in runtime_opts]

            if main_opts:
                with formatter.section('Main Arguments'):
                    formatter.write_dl(main_opts)
            if runtime_opts:
                with formatter.section('Runtime Options'):
                    formatter.write_dl(runtime_opts)
            if other_opts:
                with formatter.section('Other Options'):
                    formatter.write_dl(other_opts)

@click.command(cls=GroupedCommand)
@click.option('-i', '--input-fasta', required=True,
              type=click.Path(exists=True, dir_okay=False),
              help='Input FASTA file to dereplicate')
@click.option('-o', '--output', required=True,
              type=click.Path(dir_okay=False),
              help='Output FASTA file with unique sequences')
@click.option('--threads', type=int,
              cls=ThreadOption,
              help='Number of threads (overrides config value)')
@click.option('--verbose', is_flag=True,
              help='Enable verbose output')
def cli(input_fasta, output, threads, verbose):
    """Dereplicate FASTA sequences using USEARCH.
    
    \b
    This command identifies and collapses identical sequences, keeping track
    of their abundance in the sequence headers.
    
    Example usage:
      qimba derep -i input.fasta -o unique.fasta --threads 8
    """
    # Get configuration
    ctx = click.get_current_context()
    config = ctx.obj['config']
    
    # Determine threads to use
    config_threads = config.get('qimba', 'threads', fallback='1')
    thread_count = str(threads) if threads else config_threads
    
    if verbose:
        click.echo(f"Input file: {input_fasta}")
        click.echo(f"Output file: {output}")
        click.echo(f"Using {thread_count} threads")
    
    # Prepare log directory using output path as reference
    log_dir = Path(output).parent / 'logs'
    log_dir.mkdir(parents=True, exist_ok=True)
    
    # Create the job
    job = Job(
        command=[
            'usearch',
            '-fastx_uniques',
            input_fasta,
            '-fastaout',
            output,
            '-sizeout',  # Include abundance information in headers
            '-threads',
            thread_count
        ],
        required_input=[input_fasta],
        required_output=[output],
        log_stderr=log_dir / f"{Path(output).stem}.derep.err",
        log_stdout=log_dir / f"{Path(output).stem}.derep.out"
    )
    
    if verbose:
        click.echo(f"Executing: {job}")
    
    try:
        result = job.run()
        
        if verbose:
            click.echo("Dereplication completed successfully")
            
            # Try to get sequence counts if verbose
            try:
                with open(input_fasta) as f:
                    input_seqs = sum(1 for line in f if line.startswith('>'))
                with open(output) as f:
                    output_seqs = sum(1 for line in f if line.startswith('>'))
                click.echo(f"Input sequences: {input_seqs:,}")
                click.echo(f"Unique sequences: {output_seqs:,}")
                click.echo(f"Reduction: {(1 - output_seqs/input_seqs)*100:.1f}%")
            except Exception as e:
                if verbose:
                    click.echo(f"Note: Couldn't get sequence counts: {e}", err=True)
        
    except FileNotFoundError as e:
        click.echo(f"Error: {e}", err=True)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        click.echo(f"Error: Dereplication failed with code {e.returncode}", err=True)
        if verbose:
            click.echo(f"Check logs in: {log_dir}")
        sys.exit(1)
    except RuntimeError as e:
        click.echo(f"Error: {e}", err=True)
        if verbose:
            click.echo(f"Check logs in: {log_dir}")
        sys.exit(1)
