from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Dict, Iterator, Optional, Union, Any, List
import csv

class SortBy(Enum):
    """Enumeration for sort options."""
    SAMPLE_ID = "sample_id"
    FORWARD_READ = "forward_read"

@dataclass
class Sample:
    """Represents a single sample with its forward and reverse reads and additional attributes."""
    id: str
    forward: Path
    reverse: Optional[Path] = None
    attributes: Dict[str, str] = None

    def __post_init__(self):
        """Initialize attributes dictionary if None."""
        if self.attributes is None:
            self.attributes = {}

    def __str__(self) -> str:
        """String representation including all attributes."""
        rev = str(self.reverse) if self.reverse else ""
        return f"{self.id}\t{self.forward}\t{rev}"

    def get_attr(self, attr: str) -> Optional[str]:
        """Get an attribute value."""
        return self.attributes.get(attr)

class SampleSheet:
    """Manages a collection of sequencing samples and their associated files."""
    REQUIRED_COLUMNS = {'Forward', 'Reverse'}
    
    def __init__(self):
        """Initialize an empty sample sheet."""
        self._samples: Dict[str, Sample] = {}
        self.columns: List[str] = []

    def add_sample(self, sample_id: str, forward: Union[str, Path], 
                  reverse: Optional[Union[str, Path]] = None,
                  attributes: Dict[str, str] = None) -> None:
        """
        Add a new sample to the sample sheet.
        
        Args:
            sample_id: Unique identifier for the sample
            forward: Path to forward reads file
            reverse: Optional path to reverse reads file
            attributes: Optional dictionary of additional attributes
            
        Raises:
            ValueError: If sample_id already exists
        """
        if sample_id in self._samples:
            raise ValueError(f"Sample {sample_id} already exists in sample sheet")
            
        # Convert strings to Path objects
        fwd = Path(forward) if isinstance(forward, str) else forward
        rev = Path(reverse) if isinstance(reverse, str) and reverse else reverse
        
        self._samples[sample_id] = Sample(sample_id, fwd, rev, attributes or {})

    def get_sample_attr(self, sample_id: str, attr: str) -> Optional[str]:
        """
        Get a sample's attribute value.
        
        Args:
            sample_id: Sample identifier
            attr: Attribute name
            
        Returns:
            Attribute value if it exists, None otherwise
            
        Raises:
            KeyError: If sample_id doesn't exist
        """
        if sample_id not in self._samples:
            raise KeyError(f"Sample not found: {sample_id}")
        
        return self._samples[sample_id].get_attr(attr)

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
            sample.id for sample in self._samples.values()
            if sample.get_attr(attr) == value
        ]

    @classmethod
    def load_from_file(cls, filepath: Union[str, Path]) -> 'SampleSheet':
        """
        Create a new SampleSheet object from an existing mapping file.
        
        Args:
            filepath: Path to the mapping file (TSV format)
            
        Returns:
            A new SampleSheet object
            
        Raises:
            ValueError: If required columns are missing or file format is invalid
        """
        sheet = cls()
        filepath = Path(filepath)
        
        with filepath.open() as f:
            reader = csv.reader(f, delimiter='\t')
            
            # Get and validate headers
            try:
                headers = next(reader)
            except StopIteration:
                raise ValueError(f"Empty mapping file: {filepath}")
            
            # Store column names
            sheet.columns = headers
            
            # First column is always sample ID
            if not headers[0].strip():
                raise ValueError("First column must contain sample IDs")
            
            # Find required columns
            col_idx = {col.strip(): idx for idx, col in enumerate(headers)}
            missing_cols = cls.REQUIRED_COLUMNS - set(col_idx.keys())
            if missing_cols:
                raise ValueError(
                    f"Missing required columns in mapping file: {', '.join(missing_cols)}"
                )
            
            # Process samples
            for row_num, row in enumerate(reader, 2):  # Start at 2 for human-readable line numbers
                if len(row) != len(headers):
                    raise ValueError(
                        f"Line {row_num}: Expected {len(headers)} columns, got {len(row)}"
                    )
                
                sample_id = row[0].strip()
                if not sample_id:
                    continue
                
                # Get required fields
                forward = row[col_idx['Forward']]
                reverse = row[col_idx['Reverse']]
                if not reverse.strip():
                    reverse = None
                
                # Get additional attributes
                attributes = {
                    col: row[idx] for col, idx in col_idx.items()
                    if col not in {'Forward', 'Reverse'} and col != headers[0]
                }
                
                sheet.add_sample(sample_id, forward, reverse, attributes)
                
        return sheet

    def save_to_file(self, filepath: Union[str, Path], 
                     absolute_paths: bool = False) -> None:
        """
        Save the sample sheet to a file.
        
        Args:
            filepath: Output file path
            absolute_paths: Whether to use absolute paths for read files
        """
        filepath = Path(filepath)
        
        with filepath.open('w') as f:
            writer = csv.writer(f, delimiter='\t', lineterminator='\n')
            
            # Write header with all columns
            writer.writerow(self.columns)
            
            # Write samples
            for sample in self:
                # Prepare row with all attributes
                row = [sample.id]
                for col in self.columns[1:]:  # Skip sample ID column
                    if col == 'Forward':
                        value = str(sample.forward.absolute() if absolute_paths else sample.forward)
                    elif col == 'Reverse':
                        value = str(sample.reverse.absolute() if absolute_paths and sample.reverse 
                                else sample.reverse or '')
                    else:
                        value = sample.get_attr(col) or ''
                    row.append(value)
                writer.writerow(row)

    def remove_sample(self, sample_id: str) -> None:
        """Remove a sample from the sample sheet."""
        if sample_id not in self._samples:
            raise KeyError(f"Sample {sample_id} not found in sample sheet")
        del self._samples[sample_id]

    def get_sample(self, sample_id: str) -> Sample:
        """Retrieve a sample by its ID."""
        if sample_id not in self._samples:
            raise KeyError(f"Sample {sample_id} not found in sample sheet")
        return self._samples[sample_id]

    def sort(self, by: Union[str, SortBy] = SortBy.SAMPLE_ID) -> 'SampleSheet':
        """Sort samples by specified criterion and return a new SampleSheet."""
        # Convert string to enum if necessary
        if isinstance(by, str):
            try:
                by = SortBy(by.lower())
            except ValueError:
                raise ValueError(f"Invalid sort criterion: {by}. "
                               f"Valid options are: {[e.value for e in SortBy]}")

        # Create new sorted sample list
        if by == SortBy.SAMPLE_ID:
            sorted_samples = sorted(self._samples.values(), key=lambda x: x.id)
        elif by == SortBy.FORWARD_READ:
            sorted_samples = sorted(self._samples.values(), key=lambda x: str(x.forward))
        else:
            raise ValueError(f"Invalid sort criterion: {by}")

        # Create new SampleSheet with sorted samples
        new_sheet = SampleSheet()
        new_sheet.columns = self.columns.copy()  # Preserve column order
        for sample in sorted_samples:
            new_sheet.add_sample(sample.id, sample.forward, sample.reverse, sample.attributes)
            
        return new_sheet

    def __iter__(self) -> Iterator[Sample]:
        """Iterate over samples in the sheet."""
        return iter(self._samples.values())

    def __len__(self) -> int:
        """Return the number of samples in the sheet."""
        return len(self._samples)

    def __str__(self) -> str:
        """Return a string representation of the sample sheet."""
        # If we have defined columns, use them
        if self.columns:
            lines = ['\t'.join(self.columns)]
            for sample in self:
                row = [sample.id]
                for col in self.columns[1:]:
                    if col == 'Forward':
                        value = str(sample.forward)
                    elif col == 'Reverse':
                        value = str(sample.reverse or '')
                    else:
                        value = sample.get_attr(col) or ''
                    row.append(value)
                lines.append('\t'.join(row))
        else:
            # Fallback to basic format if no columns are defined
            lines = ['SampleID\tForward\tReverse']
            for sample in self:
                rev = str(sample.reverse) if sample.reverse else ""
                lines.append(f"{sample.id}\t{sample.forward}\t{rev}")
        return '\n'.join(lines)