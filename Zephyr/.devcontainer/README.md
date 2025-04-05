
# Setup SSH

# Generate SSH key pair and add to Github
`ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -P '' -C "your_email@example.com"`

# Add SSH private key to ssh-agent
`eval "$(ssh-agent -s)"`
`ssh-add ~/.ssh/id_ed25519`

## Start SSH agent
On Windows: `Start-Service ssh-agent`

## (Optional) To ensure the SSH agent starts automatically on boot:
On Windows: `Set-Service ssh-agent -StartupType Automatic`