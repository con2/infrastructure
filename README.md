# Tracon infrastructure

## Ansible status as of 2025-09-01

Most of the repository is rotten. What works is setting admin SSH keys:

    uv run ansible-playbook -bK admins.yml

Some hosts are firewalled and SSH needs to hop via Riimu. See `ssh-config`.

If your SSH agent (eg. Secretive on macOS) dislikes multiple simultaneous authentication attempts, you need to run the hosts one by one by specifying eg. `-l qb1`.

Password hashes are in `group_vars/all/vault`. You need to put the vault password in `.vault_pass.txt` in the root directory of this repository. To get the vault password, ask Japsu or see [Tracon KeePassXC](https://github.com/tracon/keepassxc-tracon).

## Kubernetes stuff

Helm values files etc. (without secrets) can be found under `kubernetes/`.

## License

    ansible-tracon – 5th generation Tracon infrastructure with Ansible & Docker
    Copyright © 2015–2025 Santtu Pajukanta
    Copyright © 2016 Miika Ojamo

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
