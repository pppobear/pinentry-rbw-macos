# Fish shell completion for pinentry-rbw-macos
# Install: cp pinentry-rbw-macos.fish ~/.config/fish/completions/

# Disable file completions — this tool takes no file arguments
complete -c pinentry-rbw-macos -f

complete -c pinentry-rbw-macos -l store \
    -d 'Prompt securely and save the master password to Keychain'

complete -c pinentry-rbw-macos -l store-stdin \
    -d 'Read master password from stdin and save it to Keychain'

complete -c pinentry-rbw-macos -l clear \
    -d 'Remove the stored master password from Keychain'

complete -c pinentry-rbw-macos -l version \
    -d 'Show version information'

complete -c pinentry-rbw-macos -l help \
    -d 'Show usage information'

complete -c pinentry-rbw-macos -l ttyname -r \
    -d 'Use PATH as the terminal device'

complete -c pinentry-rbw-macos -l timeout -r \
    -d 'Cancel input after SECONDS (0 disables timeout)'

complete -c pinentry-rbw-macos -l display -r \
    -d 'Pass DISPLAY to the graphical prompt'

complete -c pinentry-rbw-macos -l no-global-grab \
    -d 'Do not request a global input grab'

complete -c pinentry-rbw-macos -l lc-messages -r -a 'en zh-Hans' \
    -d 'Select application messages'
