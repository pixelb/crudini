#!/bin/bash

trap "exit 130" INT
cleanup() { rm -f test.ini good.ini example.ini; exit; }
trap cleanup EXIT

export PATH=..:$PATH

test=0

fail() { test=$(($test+1)); echo "Test $test FAIL (line ${BASH_LINENO[0]})"; exit 1; }
ok() { test=$(($test+1)); echo "Test $test OK (line ${BASH_LINENO[0]})"; }

cp ../example.ini .

# invalid params ----------------------------------------

:> test.ini
crudini 2>/dev/null && fail
crudini --met test.ini 2>/dev/null && fail # bad mode
crudini --set 2>/dev/null && fail # no file
crudini --set test.ini  2>/dev/null && fail # no section
crudini --get 2>/dev/null && fail # no file
crudini --get test.ini '' 'name' 'val' 2>/dev/null && fail # value
crudini --get --format=bad test.ini 2>/dev/null && fail # bad format
crudini --del 2>/dev/null && fail # no file
crudini --del test.ini 2>/dev/null && fail # no section
crudini --del test.ini '' 'name' 'val' 2>/dev/null && fail # value
crudini --merge 2>/dev/null && fail # no file
crudini --merge test.ini '' 'name' 2>/dev/null && fail # param
crudini --del test.ini '' 'name' 'val' 2>/dev/null && fail # value
crudini --get --format=ggg test.ini 2>&1 | grep -q 'format not recognized' || fail
crudini --get test.ini 'DEFAULT' missing 2>&1 | grep -q 'Parameter not found' || fail
ok

# --set -------------------------------------------------

:> test.ini
crudini --set test.ini '' name val
printf '%s\n' 'name = val' > good.ini
diff -u test.ini good.ini && ok || fail

:> test.ini
crudini --set test.ini DEFAULT name val
printf '%s\n' '[DEFAULT]' 'name = val' > good.ini
diff -u test.ini good.ini && ok || fail

:> test.ini
crudini --set test.ini nonDEFAULT name val
printf '%s\n' '[nonDEFAULT]' 'name = val' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'global=val' > test.ini
crudini --set test.ini '' global valnew
printf '%s\n' 'global=valnew' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'global=val' > test.ini
crudini --set test.ini DEFAULT global valnew
printf '%s\n' '[DEFAULT]' 'global=valnew' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' '[DEFAULT]' 'global=val' > test.ini
crudini --set test.ini DEFAULT global valnew
printf '%s\n' '[DEFAULT]' 'global=valnew' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'global=val' '' '[nonDEFAULT]' 'name=val' > test.ini
crudini --set test.ini '' global valnew
printf '%s\n' 'global=valnew' '' '[nonDEFAULT]' 'name=val' > good.ini
diff -u test.ini good.ini && ok || fail

# do these --sets which test [DEFAULT] handling also with --inplace
for mode in '' '--inplace'; do
# Add '[DEFAULT]' if explicitly specified
  printf '%s\n' 'global=val' '' '[nonDEFAULT]' 'name=val' > test.ini
  crudini $mode --set test.ini DEFAULT global valnew
  printf '%s\n' '[DEFAULT]' 'global=valnew' '' '[nonDEFAULT]' 'name=val' > good.ini
  diff -u test.ini good.ini && ok || fail

  printf '%s\n' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > test.ini
  crudini $mode --set test.ini DEFAULT global val
  printf '%s\n' '[DEFAULT]' 'global = val' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > good.ini
  diff -u test.ini good.ini && ok || fail

  printf '%s\n' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > test.ini
  crudini $mode --set test.ini '' global val
  printf '%s\n' 'global = val' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > good.ini
  diff -u test.ini good.ini && ok || fail

  # Ensure '[DEFAULT]' is not duplicated
  printf '%s\n' '[DEFAULT]' > test.ini
  crudini $mode --set test.ini DEFAULT global val
  printf '%s\n' '[DEFAULT]' 'global = val' > good.ini
  diff -u test.ini good.ini && ok || fail

  # Ensure '[DEFAULT]' is not duplicated when trailing space is present
  printf '%s\n' '[DEFAULT]  ' > test.ini
  crudini $mode --set test.ini DEFAULT global val
  printf '%s\n' '[DEFAULT]  ' 'global = val' > good.ini
  diff -u test.ini good.ini && ok || fail

  # Ensure '[DEFAULT]' is not duplicated when a trailing comment is present
  printf '%s\n' '[DEFAULT] #comment' > test.ini
  crudini $mode --set test.ini DEFAULT global val
  printf '%s\n' '[DEFAULT] #comment' 'global = val' > good.ini
  diff -u test.ini good.ini && ok || fail

  # Maintain colon separation
  crudini $mode --set example.ini section1 colon val
  grep -q '^colon:val' example.ini && ok || fail

  # Maintain space separation
  crudini $mode --set example.ini section1 nospace val
  grep -q '^nospace=val' example.ini && ok || fail
done

# value is optional
:> test.ini
crudini --set test.ini '' name
printf '%s\n' 'name = ' > good.ini
diff -u test.ini good.ini && ok || fail

# value is optional
printf '%s\n' 'name=val' > test.ini
crudini --set test.ini '' name
printf '%s\n' 'name=' > good.ini
diff -u test.ini good.ini && ok || fail

# Protect against creating non parseable files (with nested [[]])
:> test.ini
crudini --set test.ini '[section]' name val 2>/dev/null && fail
test -s test.ini && fail
printf '%s\n' '[[section]]' 'name=val' > test.ini
crudini --get test.ini '[section]' name 2>/dev/null && fail
printf '%s\n' '[section]' '[name=val' > test.ini
crudini --get test.ini 'section' '[name' 2>/dev/null && fail
printf '%s\n' '[section]' 'n[ame=val' > test.ini
test $(crudini --get test.ini 'section' 'n[ame') = 'val' && ok || fail

# --existing with file creation
for mode in '' '--inplace'; do
  crudini $mode --set missing.ini '' name val 2>/dev/null && ok || fail
  rm -f missing.ini
  for emode in '' 'file' 'section' 'param'; do
    crudini $mode --existing="$emode" --set missing.ini '' name val \
      2>/dev/null && fail || ok
    test -f missing.ini && fail
  done
  rm -f missing.ini
done

# --existing[=param]
:> test.ini
crudini --set test.ini '' gname val
crudini --set --existing test.ini '' gname val2
crudini --set --existing=inval test.ini '' gname val3 2>/dev/null && fail
crudini --set --existing test.ini '' gname2 val 2>/dev/null && fail
crudini --set test.ini section1 name val
crudini --set --existing test.ini section1 name val2
crudini --set --existing test.ini section1 name2 val 2>/dev/null && fail
printf '%s\n' 'gname = val2' '' '' '[section1]' 'name = val2' > good.ini
diff -u test.ini good.ini && ok || fail

# --existing=section
:> test.ini
crudini --set test.ini '' gname val
crudini --set --existing='section' test.ini '' gname val2
crudini --set --existing='section' test.ini '' gname2 val 2>/dev/null || fail
crudini --set test.ini section1 name val
crudini --set --existing='section' test.ini section1 name val2
crudini --set --existing='section' test.ini section1 name2 val 2>/dev/null || fail
printf '%s\n' 'gname = val2' 'gname2 = val' \
       '' '' '[section1]' 'name = val2' 'name2 = val' > good.ini
diff -u test.ini good.ini && ok || fail

# --get -------------------------------------------------

# basic get
test "$(crudini --get example.ini section1 cAps)" = 'not significant' && ok || fail

# get sections
crudini --get example.ini > test.ini
printf '%s\n' DEFAULT section1 'empty section' non-sh-compat list > good.ini
diff -u test.ini good.ini && ok || fail

# get implicit default section
crudini --get example.ini '' > test.ini
printf '%s\n' 'global' > good.ini
diff -u test.ini good.ini || fail
crudini --format=ini --get example.ini '' > test.ini
printf '%s\n' '[DEFAULT]' 'global = supported' > good.ini
diff -u test.ini good.ini || fail
ok

# get explicit default section
crudini --get example.ini DEFAULT > test.ini
printf '%s\n' 'global' > good.ini
diff -u test.ini good.ini || fail
crudini --get --format ini example.ini DEFAULT > test.ini
printf '%s\n' '[DEFAULT]' 'global = supported' > good.ini
diff -u test.ini good.ini || fail
ok

# get section1 in ini format
crudini --format=ini --get example.ini section1 > test.ini
diff -u test.ini section1.ini && ok || fail

# get section1 in sh format
crudini --format=sh --get example.ini section1 > test.ini
diff -u test.ini section1.sh && ok || fail

# empty DEFAULT is not printed
printf '%s\n' '[DEFAULT]' '#comment' '[section1]' > test.ini
test "$(crudini --get test.ini)" = 'section1' || fail
printf '%s\n' '#comment' '[section1]' > test.ini
test "$(crudini --get test.ini)" = 'section1' || fail
ok

# missing bits
:> test.ini
crudini --get missing.ini 2>/dev/null && fail
test "$(crudini --get test.ini)" = '' || fail
crudini --get test.ini '' || fail
crudini --get test.ini '' 'missing' 2>/dev/null && fail
ok

# --merge -----------------------------------------------

# XXX: An empty default section isn't merged
:> test.ini
printf '%s\n' '[DEFAULT]' '#comment' '[section1]' |
crudini --merge test.ini || fail
printf '%s\n' '[section1]' > good.ini
diff -u test.ini good.ini && ok || fail

:> test.ini
printf '%s\n' '[DEFAULT]' 'name=val' '[section1]' |
crudini --merge test.ini || fail
printf '%s\n' '[DEFAULT]' 'name = val' '' '[section1]' > good.ini
diff -u test.ini good.ini && ok || fail

:> test.ini
printf '%s\n' 'name=val' |
crudini --merge test.ini || fail
printf '%s\n' 'name = val' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name = val2' |
crudini --merge test.ini || fail
printf '%s\n' 'name=val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini || fail
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'name = val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini '' || fail
printf '%s\n' 'name = val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' '[DEFAULT]' 'name=val2' |
crudini --merge test.ini || fail
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' '[DEFAULT]' 'name=val2' |
crudini --merge test.ini '' || fail
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini '' || fail
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini DEFAULT || fail
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini new || fail
printf '%s\n' 'name=val1' '' '' '[new]' 'name = val2' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge --existing test.ini new 2>/dev/null && fail || ok

printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name2=val2' |
crudini --merge --existing test.ini || fail
printf '%s\n' 'name=val1' > good.ini
diff -u test.ini good.ini && ok || fail

printf '%s\n' 'name=val1' '[section1]' 'name=val2' > test.ini
printf '%s\n' 'name=val1a' '[section1]' 'name=val2a' |
crudini --merge --existing test.ini || fail
printf '%s\n' 'name=val1a' '[section1]' 'name=val2a' > good.ini
diff -u test.ini good.ini && ok || fail

# All input sections merged to a specific section
printf '%s\n' 'name=val1' '[section1]' 'name=val2' > test.ini
printf '%s\n' 'name=val2a' '[section2]' 'name2=val' |
crudini --merge test.ini 'section1' || fail
printf '%s\n' 'name=val1' '[section1]' 'name=val2a' 'name2 = val' > good.ini
diff -u test.ini good.ini && ok || fail

# Maintain case for existing parameters
printf '%s\n' '[section]' 'name=val' > test.ini
printf '%s\n' '[section]' 'Name=val' |
crudini --merge test.ini || fail
printf '%s\n' '[section]' 'name=val'> good.ini
diff -u test.ini good.ini && ok || fail

# Honor case for new parameters (spacing not currently honored)
printf '%s\n' '[section]' 'name1=val' > test.ini
printf '%s\n' '[section]' 'Name2=val' |
crudini --merge test.ini || fail
printf '%s\n' '[section]' 'name1=val' 'Name2 = val' > good.ini
diff -u test.ini good.ini && ok || fail

# Note iniparse currently matches sections case insensitively
printf '%s\n' '[section1]' 'name=val1' > test.ini
printf '%s\n' '[Section1]' 'name=val2' |
crudini --merge --existing 2>/dev/null test.ini && fail || ok
printf '%s\n' '[Section1]' 'name=val2' |
crudini --merge test.ini || fail
printf '%s\n' '[section1]' 'name=val1' '' '' '[Section1]' 'name = val2' > good.ini
diff -u test.ini good.ini && ok || fail

# --del -------------------------------------------------

for sec in '' '[DEFAULT]'; do
  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini '' noname || fail
  crudini --del --existing test.ini '' noname 2>/dev/null && fail
  crudini --del test.ini '' name || fail
  :> good.ini
  [ "$sec" ] && printf '%s\n' $sec > good.ini
  diff -u test.ini good.ini && ok || fail

  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini 'DEFAULT' noname || fail
  crudini --del --existing test.ini 'DEFAULT' noname 2>/dev/null && fail
  crudini --del test.ini 'DEFAULT' name || fail
  :> good.ini
  [ "$sec" ] && printf '%s\n' $sec > good.ini
  diff -u test.ini good.ini && ok || fail

  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini nosect || fail
  crudini --del --existing=file test.ini nosect || fail
  crudini --del --existing=section test.ini nosect 2>/dev/null && fail
  crudini --del --existing=param test.ini '' noname 2>/dev/null && fail
  crudini --del --existing test.ini nosect 2>/dev/null 2>/dev/null && fail
  crudini --del --existing=param test.ini '' name || fail
  crudini --del test.ini '' || fail
  :> good.ini
  diff -u test.ini good.ini && ok || fail

  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini nosect || fail
  crudini --del --existing=file test.ini nosect || fail
  crudini --del --existing=section test.ini nosect 2>/dev/null && fail
  crudini --del --existing=param test.ini 'DEFAULT' noname 2>/dev/null && fail
  crudini --del --existing test.ini nosect 2>/dev/null && fail
  crudini --del test.ini 'DEFAULT' || fail
  :> good.ini
  diff -u test.ini good.ini && ok || fail
done

# --del non existing sections/params shouldn't give an error
printf '%s\n' '[section]' 'name = val' > test.ini
crudini --verbose --del test.ini nosect 2>&1 | grep -q ^unchanged || fail
crudini --verbose --del test.ini nosect noname 2>&1 | grep -q ^unchanged || fail
crudini --verbose --del test.ini section noname 2>&1 | grep -q ^unchanged || fail
crudini --verbose --del test.ini section noname 2>&1 | grep -q ^unchanged || fail
crudini --verbose --del --list test.ini section noname val 2>&1 | grep -q ^unchanged || fail
crudini --verbose --del --list test.ini nosect noname val 2>&1 | grep -q ^unchanged || fail
crudini --verbose --del test.ini section 2>&1 | grep -q ^changed || fail
test -s test.ini && fail || ok

# --del non existing file shouldn't create an empty file
crudini --verbose --del missing.ini section 2>&1 | grep -q ^unchanged || fail
crudini --existing --del missing.ini section 2>/dev/null && fail
test -f missing.ini && fail || ok

# --get-lines --------------------------------------------

crudini --get --format=lines example.ini section1 > test.ini || fail
diff -u test.ini section1.lines && ok || fail

crudini --get --format=lines example.ini > test.ini || fail
diff -u test.ini example.lines && ok || fail

# --list -------------------------------------------------

# Add new item to list
crudini --list --set example.ini list list1 v3 || fail
test "$(crudini --get example.ini list list1)" = 'v1, v2, v3' && ok || fail

# Ensure item in list
crudini --list --set example.ini list list1 v3 || fail
test "$(crudini --get example.ini list list1)" = 'v1, v2, v3' && ok || fail

# Delete item from list
crudini --list --del example.ini list list1 v3 || fail
test "$(crudini --get example.ini list list1)" = 'v1, v2' && ok || fail

# Delete non existing item from list
for existing in '' '--existing'; do
  crudini $existing --list --del example.ini list list1 v3 || fail
  test "$(crudini --get example.ini list list1)" = 'v1, v2' && ok || fail
done

# Add new item to list without spacing
#  auto
crudini --list --set example.ini list list2 v3 || fail
test "$(crudini --get example.ini list list2)" = 'v1,v2,v3' && ok || fail
crudini --set example.ini list list2 'v1,v2' || fail
#  explicit
crudini --list --list-sep=, --set example.ini list list2 v3 || fail
test "$(crudini --get example.ini list list2)" = 'v1,v2,v3' && ok || fail


# Delete item from list without spacing
#  auto
crudini --list --del example.ini list list2 v3 || fail
test "$(crudini --get example.ini list list2)" = 'v1,v2' && ok || fail
crudini --set example.ini list list2 'v1,v2,v3' || fail
#  explicit
crudini --list --list-sep=, --del example.ini list list2 v3 || fail
test "$(crudini --get example.ini list list2)" = 'v1,v2' && ok || fail

# Delete honoring --existing
crudini --list --existing --del example.ini nolist list1 v3 2>/dev/null && fail || ok
crudini --list --existing --del example.ini list nolist1 v3 2>/dev/null && fail || ok

# support parsing from stdin
test "$(printf '%s\n' global=1 | crudini --get - '' global)" = 1 && ok || fail

# --verbose
printf '%s\n' '[section]' 'param = value' > test.ini
crudini --verbose --set test.ini section param value 2>&1 | grep -q ^unchanged && ok || fail
crudini --verbose --set test.ini section param valuE 2>&1 | grep -q ^changed && ok || fail
crudini --verbose --del test.ini section param 2>&1 | grep -q ^changed && ok || fail
crudini --verbose --del test.ini section param 2>&1 | grep -q ^unchanged && ok || fail
crudini --verbose --del test.ini section $'multiline\nchanged:' 2>&1 | grep -q ^changed && fail || ok

# ensure leading blank lines maintained with global settings
printf '%s\n' '' 'option=1' > file.conf
printf '%s\n' '' 'option=2' > good.conf
crudini --set file.conf '' option 2 || fail
diff -u good.conf file.conf && ok || fail
rm file.conf good.conf
