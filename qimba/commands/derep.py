# qimba/commands/derep.py
import click
from pathlib import Path
import sys
import subprocess
from ..core import Job

@click.command()
@click.option('-i', '--input-fasta', required=True,
              type=click.Path(exists=True, dir_okay=False),
              help='Input FASTA file to dereplicate')
@click.option('-o', '--output', required=True,
              type=click.Path(dir_okay=False),
              help='Output FASTA file with unique sequences')
@click.option('--threads', type=int,
              help='Number of threads (overrides config value)')
@click.option('--verbose', is_flag=True,
              help='Enable verbose output')
def cli(input_fasta, output, threads, verbose):
    """Dereplicate FASTA sequences using USEARCH.
    
    This command identifies and collapses identical sequences, keeping track
    of their abundance in the sequence headers.
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
