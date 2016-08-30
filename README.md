# Tracon infrastructure

## Vault

There are numerous vaults for Secret Stuff™. You need to put the vault password in `.vault_pass.txt` in the root directory of this repository. To get the vault password, ask Japsu.

## Trying stuff out locally

If you're lucky, Vagrant might be configured for some part of the repository so you can try it out locally.

    vagrant up

## Putting stuff in the cloud

Use eg. `-l neula.kompassi.eu` to limit the scope to single machines, or `-t nginx,ssh` to limit to certain tags.

    ansible-playbook --vault-password-file=.vault_pass.txt -bK tracon.yml


## License

    ansible-tracon – 5th generation Tracon infrastructure with Ansible & Docker
    Copyright © 2016 Santtu Pajukanta

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
