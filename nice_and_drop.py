#!/usr/bin/python
import os
import pwd
import sys

# split args
username = sys.argv[1]
nice = int(sys.argv[2])
path = sys.argv[3]
args = sys.argv[3:]

# change nice
os.nice(nice)

# drop to user
pwd_entry = pwd.getpwnam(username)

os.setgid(pwd_entry.pw_gid)
os.setuid(pwd_entry.pw_uid)

# exec the command
print(path, args)
os.execv(path, args)

