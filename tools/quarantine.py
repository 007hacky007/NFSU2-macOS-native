"""macOS's com.apple.quarantine on the game data, for the files the Builder writes itself.

A file unpacked from a disc image or zip is written anew and would not carry the download's
quarantine, so tools/install_from_discs.py and tools/disc.py put the image's value on what
they unpack. Python has no xattr calls on macOS, hence libc through ctypes. Elsewhere (no
xattrs) everything here does nothing.
"""
import ctypes
import ctypes.util
import os
import subprocess

NAME = b'com.apple.quarantine'
XATTR_NOFOLLOW = 0x0001
ENOATTR = 93

_libc = None
if os.uname().sysname == 'Darwin':
    _libc = ctypes.CDLL(ctypes.util.find_library('c'), use_errno=True)
    _libc.getxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t,
                               ctypes.c_uint32, ctypes.c_int]
    _libc.getxattr.restype = ctypes.c_ssize_t
    _libc.setxattr.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t,
                               ctypes.c_uint32, ctypes.c_int]
    _libc.setxattr.restype = ctypes.c_int


def read(path):
    """The quarantine value of `path` (bytes), or None when it has none."""
    if _libc is None or path is None:
        return None
    buf = ctypes.create_string_buffer(1024)
    n = _libc.getxattr(os.fsencode(path), NAME, buf, len(buf), 0, XATTR_NOFOLLOW)
    if n < 0:
        err = ctypes.get_errno()
        if err == ENOATTR:
            return None
        raise OSError(err, os.strerror(err), str(path))
    return buf.raw[:n]


def write(path, value):
    """Puts `value` (from read()) on `path`; nothing when it is None. Raises when it cannot."""
    if value is None or _libc is None:
        return
    if _libc.setxattr(os.fsencode(path), NAME, value, len(value), 0, XATTR_NOFOLLOW):
        err = ctypes.get_errno()
        raise OSError(err, f'could not keep the quarantine: {os.strerror(err)}', str(path))


def quarantined(folder):
    """The paths under `folder` (relative, '.' for itself) that carry a quarantine."""
    result = subprocess.run(['/usr/bin/find', '.', '-xattrname', NAME.decode()], cwd=folder,
                            capture_output=True, text=True, check=True)
    return set(result.stdout.splitlines())


def check_kept(source, copy):
    """Raises unless everything quarantined in `source` (a file or folder) is in `copy` too."""
    if _libc is None:
        return
    if os.path.isdir(source) and not os.path.islink(source):
        lost = sorted(quarantined(source) - quarantined(copy))
    else:
        lost = [os.path.basename(source)] if read(source) is not None and read(copy) is None else []
    if lost:
        raise OSError(f'the copy of {source} lost the quarantine of {", ".join(lost[:5])}')
