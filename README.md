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
wget -qO- https://raw.githubusercontent.com/mkelk/omarchy-fast/main/bootstrap.sh | bash
```

Or with curl:

```bash
curl -fsSL https://raw.githubusercontent.com/mkelk/omarchy-fast/main/bootstrap.sh | bash
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

The `setup.sh` script copies your custom migrations into Omarchy's migrations directory with auto-incremented timestamps. This ensures they always run after existing Omarchy migrations. Benefits:
- Version control your migrations with Git
- Works on any Omarchy version, past or future
- Migrations are automatically numbered higher than existing ones
- Re-run setup to install new migrations from your repo
- Share your Omarchy setup with others

## Creating Custom Migrations

### Manual Creation

Create a new migration file in the `migrations/` directory. Use any timestamp - the setup script will renumber it:

```bash
# Create with any timestamp and description (timestamp will be auto-adjusted)
touch migrations/0000000000_install_my_app.sh
chmod +x migrations/0000000000_install_my_app.sh
```

The setup script will automatically copy this with a timestamp higher than all existing Omarchy migrations.

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

- `1763216799_install_vscode.sh` - Installs Visual Studio Code (included as example)
  - The actual timestamp will be auto-adjusted when installed to be higher than existing Omarchy migrations

## Workflow

1. **Create/edit migrations** in this repository (`migrations/` directory)
2. **Commit and push** to Git for version control
3. **Run setup script** - copies migrations to Omarchy with correct timestamps
4. **Run `omarchy-migrate`** - applies the new migrations
5. **On new systems** - bootstrap clones repo and setup installs migrations automatically

## Managing Migrations

### Running Migrations

```bash
omarchy-migrate
```

This will run all pending migrations. Already-completed migrations are skipped automatically.

### Skipping Failed Migrations

If a migration fails, you'll be prompted to skip it or abort. Skipped migrations won't run again.

### Adding New Migrations

After creating a new migration in your repo:

```bash
# Add new migration to your repo
nvim migrations/0000000000_install_neovim.sh
# Save and commit

# Re-run setup to install it
./setup.sh

# Run the new migration
omarchy-migrate
```

### Updating Existing Migrations

Since migrations are copied (not symlinked), you need to:
1. Edit the migration in your repo
2. Remove the old migration from Omarchy: `rm ~/.local/share/omarchy/migrations/*_description.sh`
3. Remove its state marker: `rm ~/.local/state/omarchy/migrations/*_description.sh`
4. Re-run setup: `./setup.sh`
5. Run migrations: `omarchy-migrate`

## Repository Structure

```
omarchy-fast/
├── README.md                        # This file
├── bootstrap.sh                     # One-command installer
├── setup.sh                         # Copies migrations with auto-timestamps
└── migrations/                      # Your custom migration scripts
    └── 1763216799_install_vscode.sh # Timestamps are auto-adjusted during install
```

## Tips

- Use descriptive names for migrations: `{timestamp}_{description}.sh`
- The timestamp in your repo doesn't matter - it will be auto-adjusted during setup
- Make migrations idempotent when possible (safe to run multiple times)
- Test migrations before committing
- Keep migrations focused on a single task
- Document complex migrations with comments
- Re-run `./setup.sh` anytime you add new migrations to your repo

## License

MIT
