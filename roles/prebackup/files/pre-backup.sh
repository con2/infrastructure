#!/bin/bash
for script in /etc/pre-backup.d/*; do
    if [[ -x "$script" ]]; then
        $script
    fi
done
