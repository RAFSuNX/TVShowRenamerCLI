```markdown
# TV Series File Renamer

A robust bash script for organizing TV series files into season-based directory structures with consistent naming conventions.

## Features

- Bulk rename TV episode files with user confirmation
- Season-based directory organization
- Custom season subfolders (e.g., part01, finale)
- Smart episode number detection from filenames
- Dual audio track support tagging
- Dry run mode for testing
- Conflict detection and prevention
- Detailed rename summary preview
- Persistent configuration support
- Comprehensive logging

## Requirements

- Bash 4.0 or newer
- GNU Core Utilities
- Linux/Unix-based OS

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/tv-series-renamer.git
cd tv-series-renamer
```

2. Make the script executable:
```bash
chmod +x tvrenamer.sh
```

## Usage

### Basic Command
```bash
./tvrenamer.sh
```

### Options
```bash
-y          Auto-confirm all actions
-d          Dry run mode (no actual changes)
-c FILE     Use custom config file
```

### Example Workflow

1. Run the script:
```bash
./tvrenamer.sh
```

2. Follow prompts:
```
TV Series Organizer (Custom Season Parts)
-----------------------------------------
Enter series folder path: /path/to/your/files
Enter series title: Your Series Name
Dual Audio? (y/n): y
Enter main season number: 2
Enter season part/subfolder (optional): part01
```

3. Review summary:
```
Renaming Summary:
────────────────────
Original: S01E04.mkv
Renamed: Your_Series_S02E04_Dual_1080p.mkv

Total files to process: 5
Proceed with renaming? (y/n):
```

## Configuration

Create `~/.tvrenamerrc` for default settings:
```bash
# Default configuration
dual_audio="y"
season_format="season%02d"
```

## Key Features

### Episode Number Handling
- Auto-incrementing episode counter
- Smart number detection from filenames
- Leading zero correction (08 → 8)
- Conflict prevention for existing episodes

### Directory Management
- Automatic season folder creation
- Custom subfolder support
- Empty directory cleanup
- Existing season detection

### Safety Features
- File conflict detection
- Comprehensive logs (tv_rename_*.log)
- Dry run mode
- User confirmation prompts

## Workflow

1. File scanning (main directory only)
2. Season selection with existing detection
3. Episode number input with smart suggestions
4. Summary confirmation
5. Batch renaming
6. Post-process cleanup

## Troubleshooting

Common Issues:
- **Permission Denied**: Run with `sudo` or check directory permissions
- **Invalid Numbers**: Enter numeric values only for season/episode
- **File Conflicts**: Script automatically skips existing files
- **Encoding Issues**: Ensure filenames use standard characters

## Contributing

1. Fork the repository
2. Create feature branch
3. Submit Pull Request

## License

MIT License - See LICENSE file for details
```

This README provides comprehensive documentation while maintaining professional formatting suitable for GitHub. It includes:
- Clear installation instructions
- Usage examples
- Configuration guidance
- Troubleshooting tips
- Feature explanations
- Contribution guidelines
- License information

The markdown formatting ensures readability on GitHub without relying on emojis or special characters.
