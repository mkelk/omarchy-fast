# omarchy-fast

Fast-start setup for Omarchy with custom migrations. This repository provides a streamlined way to manage and version-control your personal Omarchy system configurations and installations.

## What is Omarchy?

[Omarchy](https://github.com/basecamp/omarchy) is a beautiful, modern & opinionated Linux distribution by DHH. It uses a migration-based system to manage system configurations and software installations.

## Quick Start

### Prerequisites

- Omarchy must be installed on your system
- Git must be installed

### Installation

Run this single command to bootstrap everything:

```bash
wget -qO- https://raw.githubusercontent.com/melk/omarchy-fast/main/bootstrap.sh | bash
```

Or with curl:

```bash
curl -fsSL https://raw.githubusercontent.com/melk/omarchy-fast/main/bootstrap.sh | bash
```

Then run the migrations:

```bash
omarchy-migrate
```

**What this does:**
1. Checks that Omarchy is installed
2. Clones this repository to `~/omarchy-fast`
3. Symlinks your custom migrations into Omarchy
4. You're ready to run `omarchy-migrate`!

## How It Works

### Omarchy Migrations

Omarchy uses shell scripts in `~/.local/share/omarchy/migrations/` to manage system changes. Each migration:
- Is a shell script named with a Unix timestamp (e.g., `1700000000_install_vscode.sh`)
- Runs once and is tracked in `~/.local/state/omarchy/migrations/`
- Can install software, configure settings, or make any system changes

### This Repository

The `setup.sh` script symlinks your custom migrations from this repo into Omarchy's migrations directory. This allows you to:
- Version control your migrations with Git
- Edit migrations in your repo
- Re-run `omarchy-migrate` to apply changes
- Share your Omarchy setup with others

## Creating Custom Migrations

### Manual Creation

Create a new migration file in the `migrations/` directory:

```bash
# Create with timestamp and description
touch migrations/$(date +%s)_install_my_app.sh
chmod +x migrations/$(date +%s)_install_my_app.sh
```

### Migration Template

```bash
#!/bin/bash
set -eEo pipefail

echo "Installing My Application..."

# Your installation commands here
sudo pacman -S --noconfirm my-application

echo "✅ Installation complete!"
echo "Migration completed successfully!"
```

### Example Migrations

- `1700000000_install_vscode.sh` - Installs Visual Studio Code (included as example)

## Workflow

1. **Edit migrations** in this repository
2. **Commit and push** to Git for version control
3. **Run migrations** with `omarchy-migrate` to apply changes
4. **Re-run setup** on new systems: just clone and run `./setup.sh`

## Managing Migrations

### Running Migrations

```bash
omarchy-migrate
```

This will run all pending migrations. Already-completed migrations are skipped automatically.

### Skipping Failed Migrations

If a migration fails, you'll be prompted to skip it or abort. Skipped migrations won't run again.

### Editing Existing Migrations

Since migrations are symlinked, you can edit them directly in this repo:

```bash
nvim migrations/1700000000_install_vscode.sh
# Make your changes and save
omarchy-migrate  # Skipped - already ran
```

To re-run an edited migration, remove its state file:

```bash
rm ~/.local/state/omarchy/migrations/1700000000_install_vscode.sh
omarchy-migrate  # Will run again
```

## Repository Structure

```
omarchy-fast/
├── README.md          # This file
├── setup.sh           # Setup script to symlink migrations
└── migrations/        # Your custom migration scripts
    └── 1700000000_install_vscode.sh
```

## Tips

- Use descriptive names for migrations: `{timestamp}_{description}.sh`
- Make migrations idempotent when possible (safe to run multiple times)
- Test migrations before committing
- Keep migrations focused on a single task
- Document complex migrations with comments

## License

MIT
