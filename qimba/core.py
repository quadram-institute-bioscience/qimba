from pathlib import Path
from typing import Dict, List, Optional, Any, Union, Sequence
import csv
import subprocess
import shlex
import sys
from datetime import datetime
import tempfile
class Job:
    """
    Represents a system command to be executed with input/output validation and logging.
    """
    def __init__(
        self,
        command: Union[str, Sequence[str]],
        required_input: Optional[Sequence[str]] = None,
        required_output: Optional[Sequence[str]] = None,
        log_stderr: Optional[str] = None,
        log_stdout: Optional[str] = None,
        shell: bool = False
    ):
        """
        Initialize a job with command and validation parameters.
        
        Args:
            command: Command to execute (string or list of arguments)
            required_input: List of input files that must exist before execution
            required_output: List of output files that must be created after execution
            log_stderr: Path to file for stderr logging
            log_stdout: Path to file for stdout logging
            shell: Whether to run command through shell
        """
        # Convert command to list if it's a string
        self.command = command if isinstance(command, (list, tuple)) else shlex.split(command)
        self.required_input = required_input or []
        self.required_output = required_output or []
        self.log_stderr = log_stderr
        self.log_stdout = log_stdout
        self.shell = shell
        
        # Store paths as Path objects
        self.required_input = [Path(p) for p in self.required_input]
        self.required_output = [Path(p) for p in self.required_output]
        if self.log_stderr:
            self.log_stderr = Path(self.log_stderr)
        if self.log_stdout:
            self.log_stdout = Path(self.log_stdout)
    
    def _validate_inputs(self) -> None:
        """Check if all required input files exist."""
        for input_file in self.required_input:
            if not input_file.exists():
                raise FileNotFoundError(
                    f"Required input file not found: {input_file}"
                )
    
    def _validate_outputs(self) -> None:
        """Check if all required output files were created."""
        for output_file in self.required_output:
            if not output_file.exists():
                raise RuntimeError(
                    f"Required output file was not created: {output_file}"
                )
    
    def _ensure_log_dirs(self) -> None:
        """Ensure log file directories exist."""
        for log_file in [self.log_stderr, self.log_stdout]:
            if log_file:
                log_file.parent.mkdir(parents=True, exist_ok=True)
    
    def _write_command_to_logs(self) -> None:
        """Write command and timestamp to log files."""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        header = f"\n{'='*80}\n{timestamp}\nCommand: {' '.join(map(str, self.command))}\n{'='*80}\n"
        
        for log_file in [self.log_stderr, self.log_stdout]:
            if log_file:
                with open(log_file, 'a') as f:
                    f.write(header)
    
    def run(self, check: bool = True) -> subprocess.CompletedProcess:
        """
        Execute the command with validation and logging.
        
        Args:
            check: If True, raise CalledProcessError if command returns non-zero
            
        Returns:
            CompletedProcess instance with return code and output
            
        Raises:
            FileNotFoundError: If required input files don't exist
            RuntimeError: If required output files aren't created
            subprocess.CalledProcessError: If command fails and check=True
        """
        # Validate inputs
        self._validate_inputs()
        
        # Ensure log directories exist
        self._ensure_log_dirs()
        
        # Prepare file handles for logging
        stderr = (
            open(self.log_stderr, 'a') if self.log_stderr
            else subprocess.PIPE
        )
        stdout = (
            open(self.log_stdout, 'a') if self.log_stdout
            else subprocess.PIPE
        )
        
        try:
            # Write command to logs
            self._write_command_to_logs()
            
            # Run command
            result = subprocess.run(
                self.command,
                stdout=stdout,
                stderr=stderr,
                shell=self.shell,
                check=check,
                text=True
            )
            
            # Validate outputs
            self._validate_outputs()
            
            return result
            
        finally:
            # Close file handles if we opened them
            if stderr != subprocess.PIPE:
                stderr.close()
            if stdout != subprocess.PIPE:
                stdout.close()
    
    def __str__(self) -> str:
        """Return string representation of the command."""
        return ' '.join(map(str, self.command))


class Mapping:
    """
    Represents a sample mapping file with mandatory Sample ID, Forward, and Reverse columns.
    Any additional columns become sample attributes.
    """
    REQUIRED_COLUMNS = {'Sample ID', 'Forward', 'Reverse'}
    
    def __init__(self, mapping_file: str):
        """
        Initialize mapping from a TSV file.
        
        Args:
            mapping_file: Path to TSV mapping file
        
        Raises:
            ValueError: If required columns are missing or file format is invalid
        """
        self.mapping_file = Path(mapping_file)
        self.samples: Dict[str, Dict[str, Any]] = {}
        self.columns: List[str] = []
        
        self._load_mapping()
    
    def _load_mapping(self) -> None:
        """Parse the mapping file and populate the samples dictionary."""
        with open(self.mapping_file, 'r') as f:
            reader = csv.reader(f, delimiter='\t')
            
            # Get and validate headers
            try:
                self.columns = next(reader)
            except StopIteration:
                raise ValueError(f"Empty mapping file: {self.mapping_file}")
            
            # Check for required columns
            missing_cols = self.REQUIRED_COLUMNS - set(self.columns)
            if missing_cols:
                raise ValueError(
                    f"Missing required columns in mapping file: {', '.join(missing_cols)}"
                )
            
            # Get column indices
            col_idx = {col: idx for idx, col in enumerate(self.columns)}
            
            # Parse each sample
            for row_num, row in enumerate(reader, 2):  # Start at 2 for human-readable line numbers
                if len(row) != len(self.columns):
                    raise ValueError(
                        f"Line {row_num}: Expected {len(self.columns)} columns, "
                        f"got {len(row)}"
                    )
                
                # Get sample ID and create sample dict
                sample_id = row[col_idx['Sample ID']]
                if sample_id in self.samples:
                    raise ValueError(f"Duplicate Sample ID found: {sample_id}")
                
                # Create sample entry with all attributes
                sample_data = {
                    col: row[idx] for col, idx in col_idx.items()
                }
                
                # Validate read files exist
                forward = Path(sample_data['Forward'])
                reverse = Path(sample_data['Reverse'])
                
                if not forward.exists():
                    raise ValueError(
                        f"Forward read file not found for sample {sample_id}: {forward}"
                    )
                if not reverse.exists():
                    raise ValueError(
                        f"Reverse read file not found for sample {sample_id}: {reverse}"
                    )
                
                self.samples[sample_id] = sample_data
    
    def get_sample_attr(self, sample_id: str, attr: str) -> Optional[str]:
        """
        Get a sample's attribute value.
        
        Args:
            sample_id: Sample identifier
            attr: Attribute name (column from mapping file)
            
        Returns:
            Attribute value if it exists, None otherwise
        
        Raises:
            KeyError: If sample_id doesn't exist
        """
        if sample_id not in self.samples:
            raise KeyError(f"Sample not found: {sample_id}")
        
        return self.samples[sample_id].get(attr)
    
    def get_samples_by_attr(self, attr: str, value: str) -> List[str]:
        """
        Get all sample IDs that match a specific attribute value.
        
        Args:
            attr: Attribute name
            value: Attribute value to match
            
        Returns:
            List of matching sample IDs
        """
        return [
            sample_id for sample_id, data in self.samples.items()
            if data.get(attr) == value
        ]
    
    def __iter__(self):
        """Iterate over sample IDs."""
        return iter(self.samples)
    
    def __len__(self):
        """Get number of samples."""
        return len(self.samples)
    
    def __getitem__(self, sample_id: str) -> Dict[str, Any]:
        """Get all attributes for a sample."""
        return self.samples[sample_id]
    
    def __contains__(self, sample_id: str) -> bool:
        """Check if a sample exists."""
        return sample_id in self.samples

def make_temp_dir(parent_dir='/my/temps', prefix='qimba_') -> Path:
    """Create a temporary directory in the specified parent directory."""
    parent = Path(parent_dir)
    parent.mkdir(parents=True, exist_ok=True)
    return Path(tempfile.mkdtemp(prefix=prefix, dir=parent))

import re

def extract_from_log(filepath: str, pattern: str) -> list:
    """
    Extract data from a log file using a regex pattern.
    
    Args:
        filepath (str): Path to the log file
        pattern (str): Regular expression pattern with capture groups
        
    Returns:
        list: List of matched groups or empty list if no match found
    """
    try:
        with open(filepath, 'r') as file:
            content = file.read()
            match = re.search(pattern, content)
            if match:
                # Convert matched groups to appropriate types (float or int)
                return [float(group) if '.' in group else int(group) 
                        for group in match.groups()]
            return []
    except FileNotFoundError:
        print(f"Error: File {filepath} not found")
        return []
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        return []

# Example usage:
# pattern = r"Merged \((\d+), ([.\d]+)%\)"
# results = extract_from_log("path/to/your/logfile.txt", pattern)
# if results:
#     count, percentage = results
#     print(f"Merged: {count} ({percentage}%)")