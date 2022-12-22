#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim:fileencoding=utf8
#
# Copyright © Pádraig Brady <P@draigBrady.com>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GPLv2, the GNU General Public License version 2, as
# published by the Free Software Foundation. http://gnu.org/licenses/gpl.html
from __future__ import print_function

import atexit
import sys
import contextlib
import errno
import getopt
import hashlib
import iniparse
import os
import re
import shutil
import string
import tempfile

if sys.version_info[0] >= 3:
    import shlex as pipes
    from io import StringIO
    import configparser
else:
    import pipes
    from cStringIO import StringIO
    import ConfigParser as configparser


def error(message=None):
    if message:
        sys.stderr.write(message + '\n')


def delete_if_exists(path):
    """Delete a file, but ignore file not found error.
    """
    try:
        os.unlink(path)
    except EnvironmentError as e:
        if e.errno != errno.ENOENT:
            print(str(e))
            raise


def file_is_closed(stdfile):
    if not stdfile:
        # python3 sets sys.stdin etc. to None if closed
        return True
    else:
        # python2 needs to be checked
        try:
            os.fstat(stdfile.fileno())
        except EnvironmentError as e:
            if e.errno == errno.EBADF:
                return True
    return False


# Adjustments to iniparse to optionally use name=value format (nospace)
# and support for parameters without '=' specified
class CrudiniInputFilter():
    def __init__(self, fp, iniopt):
        self.fp = fp
        self.iniopt = iniopt
        self.crudini_no_arg = False
        self.windows_eol = None
        # Note [ \t] used rather than \s to avoid adjusting \r\n when no value
        # Unicode spacing around the delimiter would be very unusual anyway
        self.delimiter_spacing = re.compile(r'(.*?)[ \t]*([:=])[ \t]*(.*)')

    def readline(self):
        line = self.fp.readline()
        # XXX: This doesn't handle ;inline comments.
        # Really should be done within iniparse.

        # Detect windows format files
        # so we can undo iniparse auto conversion to unix
        if self.windows_eol is None:
            if line:
                self.windows_eol = len(line) >= 2 and line[-2] == '\r'
            else:
                self.windows_eol = os.name == 'nt'

        if line and line[0] not in '[ \t#;\n\r':

            if '=' not in line and ':' not in line:
                self.crudini_no_arg = True
                line = line.rstrip() + ' = crudini_no_arg\n'

            if 'nospace' in self.iniopt:
                # Convert _all_ existing params. New params are handled in
                # the iniparse specialization in CrudiniConfigParser()

                # Note if we wanted an option to only convert specified params
                # we could do it with special ${value}_crudini_no_space values
                # that were then adjusted on output like for crudini_no_arg
                # But if need to remove the spacing, then should for all params

                line = self.delimiter_spacing.sub(r'\1\2\3', line)

        return line


# XXX: should be done in iniparse.  Used to
# add support for ini files without a section
class AddDefaultSection(CrudiniInputFilter):
    def __init__(self, fp, iniopt):
        CrudiniInputFilter.__init__(self, fp, iniopt)
        self.first = True

    def readline(self):
        if self.first:
            self.first = False
            return '[%s]' % iniparse.DEFAULTSECT
        else:
            return CrudiniInputFilter.readline(self)


class FileLock(object):
    """Advisory file based locking.  This should be reasonably cross platform
       and also work over distributed file systems."""
    def __init__(self, exclusive=False):
        # In inplace mode, the process must be careful to not close this fp
        # until finished, nor open and close another fp associated with the
        # file.
        self.fp = None
        self.locked = False

        if os.name == 'nt':
            # XXX: msvcrt.locking is problematic on windows
            # See the history of the portalocker implementation for example:
            # https://github.com/WoLpH/portalocker/commits/develop/portalocker
            # That would involve needing a new pywin32 dependency,
            # so instead we avoid locking on windows for now.
            def lock(self):
                self.locked = True

            def unlock(self):
                self.locked = False

        else:
            import fcntl

            def lock(self):
                operation = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
                fcntl.lockf(self.fp, operation)
                self.locked = True

            def unlock(self):
                if self.locked:
                    fcntl.lockf(self.fp, fcntl.LOCK_UN)
                self.locked = False

        FileLock.lock = lock
        FileLock.unlock = unlock


class LockedFile(FileLock):
    """Open a file with advisory locking.  This provides the Isolation
       property of ACID, to avoid missing writes.  In addition this provides AC
       properties of ACID if crudini is the only logic accessing the ini file.
       This should work on most platforms and distributed file systems.

       Caveats in --inplace mode:
        - File must be writeable
        - File should be generally non readable to avoid read lock DoS.
       Caveats in replace mode:
        - Less responsive when there is contention."""

    def __init__(self, filename, operation, inplace, create):

        self.fp_cmp = None
        self.filename = filename
        self.operation = operation

        FileLock.__init__(self, operation != "--get")

        atexit.register(self.delete)

        open_mode = os.O_RDONLY
        open_args = {}
        if operation != "--get":
            # We're only reading here, but we check now for write
            # permissions we'll need in --inplace case to avoid
            # redundant processing.
            # Also an exclusive lock needs write perms anyway.
            open_mode = os.O_RDWR

            if create and operation != '--del':
                open_mode += os.O_CREAT

            # Don't convert line endings, so we maintain CRLF in files
            if sys.version_info[0] >= 3:
                open_args = {'newline': ''}

        try:
            self.fp = os.fdopen(os.open(self.filename, open_mode, 0o666),
                                **open_args)
            if inplace:
                # In general readers (--get) are protected by file_replace(),
                # but using read lock here gives AC of the ACID properties
                # when only accessing the file through crudini even with
                # file_rewrite().
                self.lock()
            else:
                # The file may have been renamed since the open so recheck
                while True:
                    self.lock()
                    fpnew = os.fdopen(os.open(self.filename, open_mode, 0o666),
                                      **open_args)
                    if (os.name == 'nt' or
                       os.path.sameopenfile(self.fp.fileno(), fpnew.fileno())):
                        # Note we don't fpnew.close() here as that would break
                        # any existing fcntl lock (fcntl.lockf is an fcntl lock
                        # despite the name).  We don't use flock() at present
                        # as that's less consistent across platforms and may
                        # be an fcntl lock on NFS anyway for example.
                        self.fp_cmp = fpnew
                        break
                    else:
                        self.fp.close()
                        self.fp = fpnew
        except EnvironmentError as e:
            # Treat --del on a non existing file as operating on NULL data
            # which will be deemed unchanged, and thus not re{written,created}
            # We don't exit early here so that --verbose is also handled.
            if create and operation == '--del' \
               and e.errno in (errno.ENOTDIR, errno.ENOENT):
                self.fp = StringIO('')
            else:
                error(str(e))
                sys.exit(1)

    def delete(self):
        # explicit close so closed in correct order if taking lock multiple
        # times, and also explicit "delete" needed to avoid implicit __del__
        # after os module is unloaded.
        self.unlock()
        if self.fp:
            self.fp.close()
        if self.fp_cmp:
            self.fp_cmp.close()


# Note we use RawConfigParser rather than SafeConfigParser
# to avoid unwanted variable interpolation.
# Note iniparse doesn't currently support allow_no_value=True.
# Note iniparse doesn't currently support space_around_delimiters=False.
class CrudiniConfigParser(iniparse.RawConfigParser):
    def __init__(self, preserve_case=False, space_around_delimiters=True):
        iniparse.RawConfigParser.__init__(self)
        # Without the following we can't have params starting with "rem"!
        # We ignore lines starting with '%' which mercurial uses to include
        iniparse.change_comment_syntax('%;#', allow_rem=False)
        if preserve_case:
            self.optionxform = str
        # Adjust iniparse separator to default to no space around equals
        # Note this does NOT convert existing params with spaces,
        # that's done in CrudiniInputFilter.readline().
        # XXX: This couples with iniparse internals.
        if not space_around_delimiters:

            def new_ol_init(self, name, value, separator="=", *args, **kw):
                orig_ol_init(self, name, value, separator, *args, **kw)
            orig_ol_init = iniparse.ini.OptionLine.__init__
            iniparse.ini.OptionLine.__init__ = new_ol_init


class Print():
    """Use for default output format."""

    def section_header(self, section):
        """Print section header.

        :param section: str
        """

        print(section)

    def name_value(self, name, value, section=None):
        """Print parameter.

        :param name: str
        :param value: str
        :param section: str (default 'None')
        """

        if value == 'crudini_no_arg':
            value = ''
        print(name or value)


class PrintIni(Print):
    """Use for ini output format."""

    def __init__(self):
        self.sep = ' '

    def section_header(self, section):
        print("[%s]" % section)

    def name_value(self, name, value, section=None):
        if value == 'crudini_no_arg':
            value = ''
        print(name, '=', value.replace('\n', '\n '), sep=self.sep)


class PrintIniNoSpace(PrintIni):
    """Use for ini output format with no space around equals"""

    def __init__(self):
        self.sep = ''


class PrintLines(Print):
    """Use for lines output format."""

    def name_value(self, name, value, section=None):
        # Both unambiguous and easily parseable by shell. Caveat is
        # that sections and values with spaces are awkward to split in shell
        if section:
            line = '[ %s ]' % section
            if name:
                line += ' '
        if name:
            line += '%s' % name
        if value == 'crudini_no_arg':
            value = ''
        if value:
            line += ' = %s' % value.replace('\n', '\\n')
        print(line)


class PrintSh(Print):
    """Use for shell output format."""

    @staticmethod
    def _valid_sh_identifier(
        i,
        safe_chars=frozenset(string.ascii_letters + string.digits + '_')
    ):
        """Provide validation of the output identifiers as it's dangerous to
        leave validation to shell. Consider for example doing eval on this in
        shell: rm -Rf /;oops=val

        :param i: str
        :param sh_safe_id_chars: frozenset
        :return: bool
        """

        if i[0] in string.digits:
            return False
        for c in i:
            if c not in safe_chars:
                return False
        return True

    def name_value(self, name, value, section=None):
        if not PrintSh._valid_sh_identifier(name):
            error('Invalid sh identifier: %s' % name)
            sys.exit(1)
        if value == 'crudini_no_arg':
            value = ''
        sys.stdout.write("%s=%s\n" % (name, pipes.quote(value)))


class Crudini():
    mode = fmt = update = iniopt = inplace = cfgfile = output = section = \
        param = value = vlist = listsep = verbose = None

    locked_file = None
    section_explicit_default = False
    data = None
    conf = None
    added_default_section = False
    _print = None

    # The following exits cleanly on Ctrl-C,
    # while treating other exceptions as before.
    @staticmethod
    def cli_exception(type, value, tb):
        if not issubclass(type, KeyboardInterrupt):
            sys.__excepthook__(type, value, tb)

    @staticmethod
    @contextlib.contextmanager
    def remove_file_on_error(path):
        """Protect code that wants to operate on PATH atomically.
        Any exception will cause PATH to be removed.
        """
        try:
            yield
        except Exception:
            t, v, tb = sys.exc_info()
            delete_if_exists(path)
            raise t(v).with_traceback(tb)

    @staticmethod
    def file_replace(name, data):
        """Replace file as atomically as possible,
        fulfilling and AC properties of ACID.
        This is essentially using method 9 from:
        http://www.pixelbeat.org/docs/unix_file_replacement.html

        Caveats:
         - Changes ownership of the file being edited
           by non root users (due to POSIX interface limitations).
         - Loses any extended attributes of the original file
           (due to the simplicity of this implementation).
         - Existing hardlinks will be separated from the
           newly replaced file.
         - Ignores the write permissions of the original file.
         - Requires write permission on the directory as well as the file.
         - With python2 on windows we don't fulfil the A ACID property.

        To avoid the above caveats see the --inplace option.
        """
        (f, tmp) = tempfile.mkstemp(".tmp", prefix=name + ".", dir=".")

        with Crudini.remove_file_on_error(tmp):
            shutil.copystat(name, tmp)

            if hasattr(os, 'fchown') and os.geteuid() == 0:
                st = os.stat(name)
                os.fchown(f, st.st_uid, st.st_gid)

            if sys.version_info[0] >= 3:
                os.write(f, bytearray(data, 'utf-8'))
            else:
                os.write(f, data)
            # We assume the existing file is persisted,
            # so sync here to ensure new data is persisted
            # before referencing it.  Otherwise the metadata could
            # be written first, referencing the new data, which
            # would be nothing if a crash occured before the
            # data was allocated/persisted.
            os.fsync(f)
            os.close(f)

            if hasattr(os, 'replace'):  # >= python 3.3
                os.replace(tmp, name)  # atomic even on windows
            elif os.name == 'posix':
                os.rename(tmp, name)  # atomic on POSIX
            else:
                backup = tmp + '.backup'
                os.rename(name, backup)
                os.rename(tmp, name)
                delete_if_exists(backup)

            # Sync out the new directory entry to provide
            # better durability that the new inode is referenced
            # rather than continuing to reference the old inode.
            # This also provides verification in exit status that
            # this update completes.
            if os.name != 'nt':
                O_DIRECTORY = 0
                if hasattr(os, 'O_DIRECTORY'):
                    O_DIRECTORY = os.O_DIRECTORY
                dirfd = os.open(os.path.dirname(name) or '.', O_DIRECTORY)
                os.fsync(dirfd)
                os.close(dirfd)

    @staticmethod
    def file_rewrite(name, data):
        """Rewrite file inplace avoiding the caveats
        noted in file_replace().

        Caveats:
         - Not Atomic as readers may see incomplete data for a while.
         - Not Consistent as multiple writers may overlap.
         - Less Durable as existing data truncated before I/O completes.
         - Requires write access to file rather than write access to dir.
        """
        # Don't convert line endings, so we maintain CRLF in files
        open_args = {}
        if sys.version_info[0] >= 3:
            open_args = {'newline': ''}

        with open(name, 'w', **open_args) as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())

    @staticmethod
    def init_iniparse_defaultsect():
        try:
            iniparse.DEFAULTSECT
        except AttributeError:
            iniparse.DEFAULTSECT = 'DEFAULT'

    # TODO item should be items and split also
    # especially in merge mode
    @staticmethod
    def update_list(curr_val, item, mode, sep):
        curr_items = []
        use_space = True  # Perhaps have 'nospace' set this default?
        if curr_val and curr_val != 'crudini_no_arg':
            if sep is None:  # Default to comma separated
                use_space = ' ' in curr_val or ',' not in curr_val
                curr_items = [v.strip() for v in curr_val.split(",")]
            elif sep == '':  # Empty means whitespace separated
                curr_items = curr_val.split(None)

                # Find first run of whitespace to maintain current delimiter
                whitespace_re = re.compile(r'\S*(\s+)')
                first_whitespace = whitespace_re.match(curr_val)
                if first_whitespace:
                    sep = first_whitespace.group(1)
                else:
                    sep = ' '

                # Maintain empty `param =` line if present
                if sep == '\n' or sep == '\r\n':
                    if curr_val.startswith(sep):
                        curr_items.insert(0, '')
            else:
                curr_items = curr_val.split(sep)

        if mode == "--set":
            if item not in curr_items:
                curr_items.append(item)
        elif mode == "--del":
            try:
                curr_items.remove(item)
            except ValueError:
                pass

        if sep is None:
            sep = ","
            if use_space:
                sep += " "

        return sep.join(curr_items)

    def usage(self, exitval=0):
        cmd = os.path.basename(sys.argv[0])
        if exitval or file_is_closed(sys.stdout):
            output = sys.stderr
        else:
            output = sys.stdout
        output.write("""\
A utility for manipulating ini files

Usage: %s --set [OPTION]...   config_file section   [param] [value]
  or:  %s --get [OPTION]...   config_file [section] [param]
  or:  %s --del [OPTION]...   config_file section   [param] [list value]
  or:  %s --merge [OPTION]... config_file [section]

SECTION can be empty ("") or "DEFAULT" in which case,
params not in a section, i.e. global parameters are operated on.
If 'DEFAULT' is used with --set, an explicit [DEFAULT] section is added.

Options:

  --existing[=WHAT]  For --set, --del and --merge, fail if item is missing,
                       where WHAT is 'file', 'section', or 'param',
                       or if WHAT not specified; all specified items.
  --format=FMT       For --get, select the output FMT.
                       Formats are 'sh','ini','lines'
  --ini-options=OPT  Set options for handling ini files.  Options are:
                       'nospace': use format name=value not name = value
  --inplace          Lock and write files in place.
                       This is not atomic but has less restrictions
                       than the default replacement method.
  --list             For --set and --del, update a list (set) of values
  --list-sep=STR     Delimit list values with \"STR\" instead of \" ,\".
                       An empty STR means any whitespace is a delimiter.
  --output=FILE      Write output to FILE instead. '-' means stdout
  --verbose          Indicate on stderr if changes were made
  --help             Write this help to stdout
  --version          Write version to stdout
""" % (cmd, cmd, cmd, cmd)
        )
        sys.exit(exitval)

    def parse_options(self):

        # Handle optional arg to long option
        # The gettopt module should really support this
        for i, opt in enumerate(sys.argv):
            if opt == '--existing':
                sys.argv[i] = '--existing='
            elif opt == '--':
                break

        try:
            long_options = [
                'del',
                'existing=',
                'format=',
                'get',
                'help',
                'ini-options=',
                'inplace',
                'list',
                'list-sep=',
                'merge',
                'output=',
                'set',
                'verbose',
                'version'
            ]
            opts, args = getopt.getopt(sys.argv[1:], '', long_options)
        except getopt.GetoptError as e:
            error(str(e))
            self.usage(1)

        for o, a in opts:
            if o in ('--help',):
                self.usage(0)
            elif o in ('--version',):
                print('crudini 0.9.4')
                sys.exit(0)
            elif o in ('--verbose',):
                self.verbose = True
            elif o in ('--set', '--del', '--get', '--merge'):
                if self.mode:
                    error('One of --set|--del|--get|--merge can be specified')
                    self.usage(1)
                self.mode = o
            elif o in ('--format',):
                self.fmt = a
                if self.fmt not in ('sh', 'ini', 'lines'):
                    error('--format not recognized: %s' % self.fmt)
                    self.usage(1)
            elif o in ('--ini-options',):
                self.iniopt = a.split(',')
                for opt in self.iniopt:
                    if opt not in ('nospace'):
                        error('--ini-options not recognized: %s' % opt)
                        self.usage(1)
            elif o in ('--existing',):
                self.update = a or 'param'  # 'param' implies all must exist
                if self.update not in ('file', 'section', 'param'):
                    error('--existing item not recognized: %s' % self.update)
                    self.usage(1)
            elif o in ('--inplace',):
                self.inplace = True
            elif o in ('--list',):
                self.vlist = "set"  # TODO support combos of list, sorted, ...
            elif o in ('--list-sep',):
                self.listsep = a
            elif o in ('--output',):
                self.output = a

        if not self.mode:
            error('One of --set|--del|--get|--merge must be specified')
            self.usage(1)

        try:
            self.cfgfile = args[0]
            self.section = args[1]
            self.param = args[2]
            self.value = args[3]
        except IndexError:
            pass

        if not self.output:
            self.output = self.cfgfile

        if file_is_closed(sys.stdout) \
           and (self.output == '-' or self.mode == '--get'):
            error("stdout is closed")
            sys.exit(1)

        if self.cfgfile is None:
            self.usage(1)
        if self.section is None and self.mode in ('--del', '--set'):
            self.usage(1)
        if self.param is not None and self.mode in ('--merge',):
            self.usage(1)
        if self.value is not None and self.mode not in ('--set',):
            if not (self.mode == '--del' and self.vlist):
                error('A value should not be specified with %s' % self.mode)
                self.usage(1)

        if self.mode == '--merge' and self.fmt == 'sh':
            # I'm not sure how useful is is to support this.
            # printenv will already generate a mostly compat ini format.
            # If you want to also include non exported vars (from `set`),
            # then there is a format change.
            error('sh format input is not supported at present')
            sys.exit(1)

        # Protect against generating non parseable ini files
        if self.section and ('[' in self.section or ']' in self.section):
            error("section names should not contain '[' or ']': %s" %
                  self.section)
            sys.exit(1)
        if self.param and self.param.startswith('['):
            error("param names should not start with '[': %s" % self.param)
            sys.exit(1)

        if not self.iniopt:
            self.iniopt = ()
        # A "param=with=equals = value" line can not be found with --get
        # so avoid the ambiguity.  Restrict to 'nospace' to allow hack in
        # https://github.com/pixelb/crudini/issues/33#issuecomment-1151253988
        if 'nospace' in self.iniopt and self.param and '=' in self.param:
            error("param names should not contain '=': %s" % self.param)
            sys.exit(1)

        if self.fmt == 'lines':
            self._print = PrintLines()
        elif self.fmt == 'sh':
            self._print = PrintSh()
        elif self.fmt == 'ini':
            if 'nospace' in self.iniopt:
                self._print = PrintIniNoSpace()
            else:
                self._print = PrintIni()
        else:
            self._print = Print()

    def _has_default_section(self):
        fp = StringIO(self.data)
        for line in fp:
            if line.startswith('[%s]' % iniparse.DEFAULTSECT):
                return True
        return False

    def _chksum(self, data):
        h = hashlib.sha256()
        if sys.version_info[0] >= 3:
            h.update(bytearray(data, 'utf-8'))
        else:
            h.update(data)
        return h.digest()

    def _parse_file(self, filename, add_default=False, preserve_case=False):
        try:
            if self.data is None:
                # Read all data up front as this is done by iniparse anyway
                # Doing it here will avoid rereads on reparse and support
                # correct parsing of stdin
                if filename == '-':
                    self.data = sys.stdin.read()
                else:
                    self.data = self.locked_file.fp.read()
                if self.mode != '--get':
                    # compare checksums to flag any changes
                    # (even spacing or case adjustments) with --verbose,
                    # and to avoid rewriting the file if not necessary
                    self.chksum = self._chksum(self.data)

                if self.data.startswith('\n'):
                    self.newline_at_start = True
                else:
                    self.newline_at_start = False

            fp = StringIO(self.data)
            if add_default:
                fp = AddDefaultSection(fp, self.iniopt)
            else:
                fp = CrudiniInputFilter(fp, self.iniopt)

            conf = CrudiniConfigParser(preserve_case=preserve_case,
                                       space_around_delimiters=(
                                         'nospace' not in self.iniopt))
            conf.readfp(fp)
            self.crudini_no_arg = fp.crudini_no_arg
            self.windows_eol = fp.windows_eol
            return conf
        except EnvironmentError as e:
            error(str(e))
            sys.exit(1)

    def parse_file(self, filename, preserve_case=False):
        self.added_default_section = False
        self.data = None

        if filename != '-':
            self.locked_file = LockedFile(filename, self.mode, self.inplace,
                                          not self.update)
        elif file_is_closed(sys.stdin):
            error("stdin is closed")
            sys.exit(1)

        try:
            conf = self._parse_file(filename, preserve_case=preserve_case)

            if not conf.items(iniparse.DEFAULTSECT):
                # Check if there is just [DEFAULT] in a file with no
                # name=values to avoid adding a duplicate section.
                if not self._has_default_section():
                    # reparse with inserted [DEFAULT] to be able to add global
                    # opts etc.
                    conf = self._parse_file(
                        filename,
                        add_default=True,
                        preserve_case=preserve_case
                    )
                    self.added_default_section = True

        except configparser.MissingSectionHeaderError:
            conf = self._parse_file(
                filename,
                add_default=True,
                preserve_case=preserve_case
            )
            self.added_default_section = True
        except configparser.ParsingError as e:
            error(str(e))
            sys.exit(1)

        self.data = None
        return conf

    def set_name_value(self, section, param, value):
        curr_val = None

        if self.update in ('param', 'section'):
            if param is None:
                if not (
                    section == iniparse.DEFAULTSECT or
                    self.conf.has_section(section)
                ):
                    raise configparser.NoSectionError(section)
            else:
                try:
                    curr_val = self.conf.get(section, param)
                except configparser.NoSectionError:
                    if self.update == 'section':
                        raise
                except configparser.NoOptionError:
                    if self.update == 'param':
                        raise
        elif (section != iniparse.DEFAULTSECT and
                not self.conf.has_section(section)):
            if self.mode == "--del":
                return
            else:
                # Note this always adds a '\n' before the section name
                # resulting in double spaced sections or blank line at
                # the start of a new file to which a new section is added.
                # We handle the empty file case at least when writing.
                self.conf.add_section(section)

        if param is not None:
            try:
                curr_val = self.conf.get(section, param)
            except configparser.NoOptionError:
                if self.mode == "--del":
                    if self.update not in ('param', 'section'):
                        return

            if value is None:
                # Unspecified param should clear list.  This will also force
                # existing param "flags" or new params to use '=' delimiter.
                if self.vlist:
                    curr_val = ''

                if curr_val == 'crudini_no_arg':
                    # param already exists without delimiter
                    return
                elif curr_val is None and self.crudini_no_arg:
                    # some params exist without delimiter
                    # so default new param to not use one
                    value = 'crudini_no_arg'
                else:
                    # Otherwise use a delimeter
                    value = ''

            if self.vlist:
                value = self.update_list(
                    curr_val,
                    value,
                    self.mode,
                    self.listsep
                )
            self.conf.set(section, param, value)

    def command_set(self):
        """Insert a section/parameter."""

        self.set_name_value(self.section, self.param, self.value)

    def command_merge(self):
        """Merge an ini file from another ini."""

        for msection in [iniparse.DEFAULTSECT] + self.mconf.sections():
            if msection == iniparse.DEFAULTSECT:
                defaults_to_strip = {}
            else:
                defaults_to_strip = self.mconf.defaults()
            items = self.mconf.items(msection)
            set_param = False
            for item in items:
                # XXX: Note this doesn't update an item in section
                # if matching value also in default (global) section.
                if defaults_to_strip.get(item[0]) != item[1]:
                    ignore_errs = (configparser.NoOptionError,)
                    if self.section is not None:
                        msection = self.section
                    elif self.update not in ('param', 'section'):
                        ignore_errs += (configparser.NoSectionError,)
                    try:
                        set_param = True
                        self.set_name_value(msection, item[0], item[1])
                    except ignore_errs:
                        pass
            # For empty sections ensure the section header is added
            if not set_param and self.section is None:
                self.set_name_value(msection, None, None)

    def command_del(self):
        """Delete a section/parameter."""

        if self.param is None:
            if self.section == iniparse.DEFAULTSECT:
                for name in self.conf.defaults():
                    self.conf.remove_option(iniparse.DEFAULTSECT, name)
            else:
                if not self.conf.remove_section(self.section) \
                   and self.update in ('param', 'section'):
                    raise configparser.NoSectionError(self.section)
        elif self.value is None:
            try:
                if not self.conf.remove_option(self.section, self.param) \
                   and self.update == 'param':
                    raise configparser.NoOptionError(self.section, self.param)
            except configparser.NoSectionError:
                if self.update in ('param', 'section'):
                    raise
        else:  # remove item from list
            self.set_name_value(self.section, self.param, self.value)

    def command_get(self):
        """Output a section/parameter"""

        if self.fmt != 'lines':
            if self.section is None:
                if self.conf.defaults():
                    self._print.section_header(iniparse.DEFAULTSECT)
                for item in self.conf.sections():
                    self._print.section_header(item)
            elif self.param is None:
                if self.fmt == 'ini':
                    self._print.section_header(self.section)
                if self.section == iniparse.DEFAULTSECT:
                    defaults_to_strip = {}
                else:
                    defaults_to_strip = self.conf.defaults()
                for item in self.conf.items(self.section):
                    # XXX: Note this strips an item from section
                    # if matching value also in default (global) section.
                    if defaults_to_strip.get(item[0]) != item[1]:
                        if self.fmt:
                            val = item[1]
                        else:
                            val = None
                        self._print.name_value(item[0], val)
            else:
                val = self.conf.get(self.section, self.param)
                if self.fmt:
                    name = self.param
                else:
                    name = None
                self._print.name_value(name, val)
        else:
            if self.section is None:
                sections = self.conf.sections()
                if self.conf.defaults():
                    sections.insert(0, iniparse.DEFAULTSECT)
            else:
                sections = (self.section,)
            if self.param is not None:
                val = self.conf.get(self.section, self.param)
                self._print.name_value(self.param, val, self.section)
            else:
                for section in sections:
                    if section == iniparse.DEFAULTSECT:
                        defaults_to_strip = {}
                    else:
                        defaults_to_strip = self.conf.defaults()
                    items = False
                    for item in self.conf.items(section):
                        # XXX: Note this strips an item from section
                        # if matching value also in default (global) section.
                        if defaults_to_strip.get(item[0]) != item[1]:
                            val = item[1]
                            self._print.name_value(item[0], val, section)
                            items = True
                    if not items:
                        self._print.name_value(None, None, section)

    def run(self):
        if not file_is_closed(sys.stdin) and sys.stdin.isatty():
            sys.excepthook = Crudini.cli_exception

        Crudini.init_iniparse_defaultsect()
        self.parse_options()

        self.section_explicit_default = False
        if self.section == '':
            self.section = iniparse.DEFAULTSECT
        elif self.section == iniparse.DEFAULTSECT:
            self.section_explicit_default = True

        if self.mode == '--merge':
            self.mconf = self.parse_file('-', preserve_case=True)

        self.madded_default_section = self.added_default_section

        try:
            if self.mode == '--get' and self.param is None:
                # Maintain case when outputting params.
                # Note sections are handled case sensitively
                # even if optionxform is not set.
                preserve_case = True
            else:
                preserve_case = False
            self.conf = self.parse_file(self.cfgfile,
                                        preserve_case=preserve_case)

            # Take the [DEFAULT] header from the input if present
            if (
                self.mode == '--merge' and
                self.update not in ('param', 'section') and
                not self.madded_default_section and
                self.mconf.items(iniparse.DEFAULTSECT)
            ):
                self.added_default_section = self.madded_default_section

            if self.mode == '--set':
                self.command_set()
            elif self.mode == '--merge':
                self.command_merge()
            elif self.mode == '--del':
                self.command_del()
            elif self.mode == '--get':
                self.command_get()

            if self.mode != '--get':
                # XXX: Ideally we should just do conf.write(f) here, but to
                # avoid iniparse issues, we massage the data a little here
                str_data = str(self.conf.data)
                if len(str_data) and str_data[-1] != '\n':
                    str_data += '\n'

                if (
                    (
                        self.added_default_section and
                        not (
                            self.section_explicit_default and
                            self.mode in ('--set', '--merge')
                        )
                    ) or
                    (
                        self.mode == '--del' and
                        self.section == iniparse.DEFAULTSECT and
                        self.param is None
                    )
                ):
                    # See note at add_section() call above detailing
                    # where this extra \n comes from that we handle
                    # here for the edge case of new files.
                    default_sect = '[%s]\n' % iniparse.DEFAULTSECT
                    if not self.newline_at_start and \
                       str_data.startswith(default_sect + '\n'):
                        str_data = str_data[len(default_sect) + 1:]
                    else:
                        str_data = str_data.replace(default_sect, '', 1)

                if self.windows_eol:
                    # iniparse uses '\n' for new/updated items
                    # so reset all to windows format
                    str_data = str_data.replace('\r\n', '\n')
                    str_data = str_data.replace('\n', '\r\n')

                if self.crudini_no_arg:
                    spacing = '' if 'nospace' in self.iniopt else ' '
                    str_data = str_data.replace('%s=%scrudini_no_arg' %
                                                (spacing, spacing), '')

                changed = self.chksum != self._chksum(str_data)

                if self.output == '-':
                    sys.stdout.write(str_data)
                elif changed:
                    if os.name == 'nt':
                        # Close input file as Windows gives access errors on
                        # open files. For e.g. see caveats noted at:
                        # https://bugs.python.org/issue46003
                        self.locked_file.delete()

                    if self.inplace:
                        self.file_rewrite(self.output, str_data)
                    else:
                        self.file_replace(os.path.realpath(self.output),
                                          str_data)

                if self.verbose:
                    def quote_val(val):
                        return pipes.quote(val).replace('\n', '\\n')
                    what = ' '.join(map(quote_val,
                                        list(filter(bool,
                                                    [self.mode, self.cfgfile,
                                                     self.section, self.param,
                                                     self.value]))))
                    sys.stderr.write('%s: %s\n' %
                                     (('unchanged', 'changed')[changed], what))

            # Finish writing now to consistently handle errors here
            # (and while excepthook is set)
            if not file_is_closed(sys.stdout):
                sys.stdout.flush()
        except configparser.ParsingError as e:
            error('Error parsing %s: %s' % (self.cfgfile, e.message))
            sys.exit(1)
        except configparser.NoSectionError as e:
            error('Section not found: %s' % e.section)
            sys.exit(1)
        except configparser.NoOptionError:
            error('Parameter not found: %s' % self.param)
            sys.exit(1)
        except EnvironmentError as e:
            # Handle EPIPE as python 2 doesn't catch SIGPIPE
            if e.errno != errno.EPIPE:
                error(str(e))
                sys.exit(1)
            # Python3 fix for exception on exit:
            # https://docs.python.org/3/library/signal.html#note-on-sigpipe
            if not file_is_closed(sys.stdout):
                nullf = os.open(os.devnull, os.O_WRONLY)
                os.dup2(nullf, sys.stdout.fileno())


def main():
    crudini = Crudini()
    return crudini.run()


if __name__ == "__main__":
    sys.exit(main())
