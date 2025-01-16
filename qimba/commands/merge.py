# qimba/commands/derep.py
import click
from pathlib import Path
import sys
import subprocess
from ..core import *
from ..formats import *
import tempfile
import os
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
@click.option('-i', '--input-samplesheet', required=True,
              type=click.Path(exists=True, dir_okay=False),
              help='Input samplesheet')
@click.option('-o', '--output', required=True,
              type=click.Path(dir_okay=False),
              help='Output FASTQ file')
@click.option('--tmp-dir',  
              type=click.Path(dir_okay=False),
              help='Temporary directory (overrides config value)')
@click.option('--threads', type=int,
              cls=ThreadOption,
              help='Number of threads (overrides config value)')
@click.option('--verbose', is_flag=True,
              help='Enable verbose output')
def cli(input_samplesheet, output, tmp_dir, threads, verbose):
    """Merge paired end into a single file using USEARCH
    
    \b
    This command generates a merged FASTQ file
    
    Example usage:
      qimba merge -i input.tsv -o merge.fastq --threads 8
    """
    # Get configuration
    ctx = click.get_current_context()
    config = ctx.obj['config']
    
    # Determine threads to use
    config_threads = config.get('qimba', 'threads', fallback='1')
    config_tmpdir  = config.get('qimba', 'tmpdir', fallback='/tmp/')
    thread_count = str(threads) if threads else config_threads
    runtime_tmpdir = Path(tmp_dir) if tmp_dir else Path(config_tmpdir)
    runtime_tmpdir.mkdir(parents=True, exist_ok=True)

    # make new temp dir
    tmp_path = make_temp_dir(parent_dir=runtime_tmpdir)

    # Prepare log directory using output path as reference
    log_dir = tmp_path / 'logs'
    log_dir.mkdir(parents=True, exist_ok=True)

    if verbose:
        click.echo(f"Input samples: {input_samplesheet}")
        click.echo(f"Output file: {output}")
        click.echo(f"Using {thread_count} threads")
        click.echo(f"Temporary directory: {tmp_path}")
        click.echo(f"Logdir: {log_dir}")
        
    samplesheet = SampleSheet.load_from_file(input_samplesheet)
    
    # check output file
    if os.path.exists(output):
        click.echo(f"Error: {output} file already found", err=True)
        sys.exit(1)
    # now cycle through all the samples using sampleName, sample_R1 and sample_R2 and generate a temporary


    outputs = []
    for sample in samplesheet:

        tmpOutput = os.path.join(tmp_path, sample.id + '.fastq')
        job = Job(
            command=[
                'usearch',
                '-fastq_mergepairs',
                sample.forward,
                '-reverse',
                sample.reverse,
                '-relabel',
                sample.id + '.',
                '-fastqout',
                tmpOutput,
                '-threads',
                thread_count
            ],
            required_input=[sample.forward, sample.reverse],
            required_output=[tmpOutput],
            log_stderr=log_dir / f"{Path(tmpOutput).stem}.merge.err",
            log_stdout=log_dir / f"{Path(tmpOutput).stem}.merge.out"
        )

    
    
        try:
            if verbose:
                click.echo(f"Merging {sample.id}")
            job.run()
            outputs.extend(job.required_output)
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

    with Path(output).open("wb") as outfile:
        for filepath in outputs:
            if verbose:
                click.echo(f"Concatenating temporary file {filepath}")
            with filepath.open('rb') as infile:
                outfile.write(infile.read())