# Fish shell completion for pinentry-rbw-macos
# Install: cp pinentry-rbw-macos.fish ~/.config/fish/completions/

# Disable file completions — this tool takes no file arguments
complete -c pinentry-rbw-macos -f

complete -c pinentry-rbw-macos -l store \
    -d 'Prompt on /dev/tty and save the master password to Keychain'

complete -c pinentry-rbw-macos -l store-stdin \
    -d 'Read master password from stdin and save it to Keychain'

complete -c pinentry-rbw-macos -l clear \
    -d 'Remove the stored master password from Keychain'

complete -c pinentry-rbw-macos -l help \
    -d 'Show usage information'
