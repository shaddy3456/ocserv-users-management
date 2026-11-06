"""Safe wrappers around the ocpasswd binary.

All calls pass arguments as a list (no shell), so usernames and passwords
can never be interpreted as shell commands.
"""
import subprocess

OCPASSWD_BIN = "/usr/bin/ocpasswd"
OCPASSWD_FILE = "/etc/ocserv/ocpasswd"


def _run(args, stdin=None):
    cmd = ["sudo", OCPASSWD_BIN, "-c", OCPASSWD_FILE] + args
    result = subprocess.run(
        cmd,
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        timeout=30,
    )
    return result.returncode == 0


def set_password(username, password):
    """Create the user or change its password."""
    return _run(["--", username], stdin=f"{password}\n{password}\n")


def delete_user(username):
    return _run(["-d", "--", username])


def lock_user(username):
    return _run(["-l", "--", username])


def unlock_user(username):
    return _run(["-u", "--", username])
