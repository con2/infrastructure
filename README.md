# Tracon infrastructure

## Vault

There are numerous vaults for Secret Stuff™. You need to put the vault password in `.vault_pass.txt` in the root directory of this repository. To get the vault password, ask Japsu.

## Trying stuff out locally

If you're lucky, Vagrant might be configured for some part of the repository so you can try it out locally.

    vagrant up

## Putting stuff in the cloud

Use eg. `-l neula.kompassi.eu` to limit the scope to single machines, or `-t nginx,ssh` to limit to certain tags.

    ansible-playbook --vault-password-file=.vault_pass.txt -bK tracon.yml
