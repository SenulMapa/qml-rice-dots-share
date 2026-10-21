#!/usr/bin/env python3

# ported from impasto scripts/account.py, verbatim except: dropped the
# "/var/lib/impasto/faces/{user}.face.icon" greeter-shared path (that only
# exists because impasto's own `./setup system` installer populates it for
# its own SDDM theme; this repo's SDDM port at system/sddm/qml-rice/ reads
# AccountsService/~/.face directly instead, same as every other greeter, so
# there is no qml-rice-specific faces directory to add here).

"""Print the account's full name and picture as JSON.

The name is the GECOS field (what `chfn` writes), the picture the first
conventional path that exists. Both are defaults the settings can override.
"""

import json
import os
import pwd
import sys

AVATARS = (
    "~/.face",
    "~/.face.icon",
    "/var/lib/AccountsService/icons/{user}",
)


def account():
    try:
        record = pwd.getpwuid(os.getuid())
    except KeyError:
        return {"user": "", "name": "", "avatar": None}

    user = record.pw_name

    # GECOS is comma-separated (name, office, phones); only the name is used,
    # and the login name stands in when it is empty.
    name = (record.pw_gecos or "").split(",")[0].strip() or user

    avatar = None
    for candidate in AVATARS:
        path = os.path.expanduser(candidate.format(user=user))
        if os.path.isfile(path):
            avatar = path
            break

    return {"user": user, "name": name, "avatar": avatar}


def main():
    if len(sys.argv) > 1 and sys.argv[1] != "get":
        sys.stderr.write("Usage: account.py [get]\n")
        sys.exit(1)
    print(json.dumps(account()))


if __name__ == "__main__":
    main()
