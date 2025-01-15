import os
import configparser
from pathlib import Path

DEFAULT_CONFIG_PATH = os.path.expanduser("~/.config/qimba.ini")

def load_config(config_path=None):
    """Load configuration from the specified path or default location."""
    if config_path is None:
        config_path = DEFAULT_CONFIG_PATH
    
    config = configparser.ConfigParser()
    
    # Create default config if it doesn't exist
    if not os.path.exists(config_path):
        config['qimba'] = {
            'default_output_dir': '.',
            'threads': '4'
        }
        
        # Ensure directory exists
        Path(os.path.dirname(config_path)).mkdir(parents=True, exist_ok=True)
        
        with open(config_path, 'w') as configfile:
            config.write(configfile)
    else:
        config.read(config_path)
    
    return config
