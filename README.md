# crudini - A utility for manipulating ini files

## Usage:
```
crudini --set [OPTION]...   config_file section   [param] [value]
crudini --get [OPTION]...   config_file [section] [param]
crudini --del [OPTION]...   config_file section   [param] [list value]
crudini --merge [OPTION]... config_file [section]

SECTION can be empty ("") or "DEFAULT" in which case,
params not in a section, i.e. global parameters are operated on.
If 'DEFAULT' is used with --set, an explicit [DEFAULT] section is added.

```
## Options:
```

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
  --list-sep=STR     Delimit list values with "STR" instead of " ,".
                       An empty STR means any whitespace is a delimiter.
  --output=FILE      Write output to FILE instead. '-' means stdout
  --verbose          Indicate on stderr if changes were made
  --help             Write this help to stdout
  --version          Write version to stdout

```
## Examples:
```

# Add/Update a var
  crudini --set config_file section parameter value

# Add/Update a var in the root or global area.
# I.e. that's not under a [section].
  crudini --set config_file "" parameter value

# Update an existing var
  crudini --set --existing config_file section parameter value

# Add/Append a value to a comma separated list
# Note any whitespace around commas is ignored
  crudini --set --list config_file section parameter a_value

# Add/Append a value to a whitespace separated list
# Note multiline lists are supported (as newline is whitespace)
  crudini --set --list --list-sep= config_file section parameter a_value

# Delete a var
  crudini --del config_file section parameter

# Delete a section
  crudini --del config_file section

# output a value
  crudini --get config_file section parameter

# output a global value not in a section
  crudini --get config_file "" parameter

# output a section
  crudini --get config_file section

# output a section, parseable by shell
  eval "$(crudini --get --format=sh config_file section)"

# update an ini file from shell variable(s)
  echo name="$name" | crudini --merge config_file section

# merge an ini file from another ini
  crudini --merge config_file < another.ini

# compare two ini files using standard UNIX text processing
  diff <(crudini --get --format=lines file1.ini|sort) \
       <(crudini --get --format=lines file2.ini|sort)

# Rewrite ini file to use name=value format rather than name = value
  crudini --ini-options=nospace --set config_file ""

# Add/Update a var, ensuring complete file in name=value format
  crudini --ini-options=nospace --set config_file section parameter value
```
## Installation

On windows ensure a python interpreter is installed.
For example installing from https://www.python.org/downloads/
will put the py launcher and pip in the PATH.

Then ensure the iniparse module is installed by
running the following from a "cmd" prompt:

```
pip install iniparse
```

Then crudini can be invoked by downloading just the crudini.py
file and running like:

```
py crudini.py --help
```

On Linux systems crudini is generally available from your standard
package manager, and installing will also ensure the iniparse
dependency is appropriately installed on your system.
You can also download and run the single crudini.py file directly
to use latest version.
