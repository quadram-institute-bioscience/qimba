def parse_fasta(fasta_file):
    """
    Generator function to parse FASTA files.
    
    Args:
        fasta_file (str): Path to FASTA file
        
    Yields:
        tuple: (sequence_id, comments, sequence)
    """
    current_id = None
    current_comments = None
    current_sequence = []
    
    with open(fasta_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
                
            if line.startswith('>'):
                # Yield the previous sequence if it exists
                if current_id:
                    yield (current_id, current_comments, ''.join(current_sequence))
                    
                # Parse the header line
                header = line[1:].split(maxsplit=1)
                current_id = header[0]
                current_comments = header[1] if len(header) > 1 else ''
                current_sequence = []
            else:
                current_sequence.append(line)
                
        # Don't forget to yield the last sequence
        if current_id:
            yield (current_id, current_comments, ''.join(current_sequence))

