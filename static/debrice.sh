#!/bin/bash

# Function to clone and place the files from a git repository
putgitrepo() {
  # Parameters: repository URL, target directory, branch name
  local repo_url="$1"
  local target_dir="$2"
  local branch_name="${3:-master}"  # Default to 'master' if not specified

  # Create a temporary directory
  local tmp_dir=$(mktemp -d)

  # Clone the repository into the temporary directory
  git clone --recursive -b "$branch_name" --depth 1 "$repo_url" "$tmp_dir"

  # Copy the repository contents to the target directory
  cp -rfT "$tmp_dir" "$target_dir"

  # Remove the temporary directory
  rm -rf "$tmp_dir"
}

# Main script
# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Update package list and install zsh
apt update
apt install -y zsh

# Define repository and target directory
dotfilesrepo="https://github.com/shourovrm/archrice.git"
target="/home/$USER"  # Replace $USER with the actual username if needed

# Create the target directory if it doesn't exist
mkdir -p "$target"

# Run the function to clone and place the repository
putgitrepo "$dotfilesrepo" "$target"

# Remove unnecessary files
rm -f "$target/README.md" "$target/LICENSE" "$target/FUNDING.yml"

# Make zsh the default shell for the user
chsh -s $(which zsh) $USER

echo "Dotfiles have been installed in $target."
echo "Zsh has been set as the default shell for $USER."
