#!/bin/sh

trap "exit 130" INT
cleanup() { rm -f test.ini good.ini example.ini; exit; }
trap cleanup EXIT

export PATH=..:$PATH

test=0

fail() { test=$(($test+1)); echo "Test $test FAIL (line $1)"; exit 1; }
ok() { test=$(($test+1)); echo "Test $test OK (line $1)"; }

cp ../example.ini .

# invalid params ----------------------------------------

:> test.ini
crudini 2>/dev/null && fail $LINENO
crudini --met test.init 2>/dev/null && fail $LINENO # bad mode
crudini --set 2>/dev/null && fail $LINENO # no file
crudini --set test.ini  2>/dev/null && fail $LINENO # no section
crudini --get 2>/dev/null && fail $LINENO # no file
crudini --get test.ini '' 'name' 'val' 2>/dev/null && fail $LINENO # value
crudini --get --format=bad test.ini 2>/dev/null && fail $LINENO # bad format
crudini --del 2>/dev/null && fail $LINENO # no file
crudini --del test.ini 2>/dev/null && fail $LINENO # no section
crudini --del test.ini '' 'name' 'val' 2>/dev/null && fail $LINENO # value
crudini --merge 2>/dev/null && fail $LINENO # no file
crudini --merge test.ini '' 'name' 2>/dev/null && fail $LINENO # param
crudini --del test.ini '' 'name' 'val' 2>/dev/null && fail $LINENO # value
ok $LINENO

# --set -------------------------------------------------

# ---
:> test.ini
crudini --set test.ini '' name val
printf '%s\n' 'name = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
:> test.ini
crudini --set test.ini DEFAULT name val
printf '%s\n' '[DEFAULT]' 'name = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# Note blank line inserted at start
:> test.ini
crudini --set test.ini nonDEFAULT name val
printf '%s\n' '' '[nonDEFAULT]' 'name = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'global=val' > test.ini
crudini --set test.ini '' global valnew
printf '%s\n' 'global=valnew' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'global=val' > test.ini
crudini --set test.ini DEFAULT global valnew
printf '%s\n' '[DEFAULT]' 'global=valnew' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' '[DEFAULT]' 'global=val' > test.ini
crudini --set test.ini DEFAULT global valnew
printf '%s\n' '[DEFAULT]' 'global=valnew' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'global=val' '' '[nonDEFAULT]' 'name=val' > test.ini
crudini --set test.ini '' global valnew
printf '%s\n' 'global=valnew' '' '[nonDEFAULT]' 'name=val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# Add '[DEFAULT]' if explicitly specified
printf '%s\n' 'global=val' '' '[nonDEFAULT]' 'name=val' > test.ini
crudini --set test.ini DEFAULT global valnew
printf '%s\n' '[DEFAULT]' 'global=valnew' '' '[nonDEFAULT]' 'name=val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# --- 
printf '%s\n' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > test.ini
crudini --set test.ini DEFAULT global val
printf '%s\n' '[DEFAULT]' 'global = val' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > test.ini
crudini --set test.ini '' global val
printf '%s\n' 'global = val' '[nonDEFAULT1]' 'name=val' '[nonDEFAULT2]' 'name=val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# Ensure '[DEFAULT]' is not duplicated
printf '%s\n' '[DEFAULT]' > test.ini
crudini --set test.ini DEFAULT global val
printf '%s\n' '[DEFAULT]' 'global = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# Ensure '[DEFAULT]' is not duplicated when trailing space is present
printf '%s\n' '[DEFAULT]  ' > test.ini
crudini --set test.ini DEFAULT global val
printf '%s\n' '[DEFAULT]  ' 'global = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# Ensure '[DEFAULT]' is not duplicated when a trailing comment is present
printf '%s\n' '[DEFAULT] #comment' > test.ini
crudini --set test.ini DEFAULT global val
printf '%s\n' '[DEFAULT] #comment' 'global = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# Maintain colon separation
crudini --set example.ini section1 colon val
grep -q '^colon:val' example.ini && ok $LINENO || fail $LINENO

# ---
# Maintain space separation
crudini --set example.ini section1 nospace val
grep -q '^nospace=val' example.ini && ok $LINENO || fail $LINENO

# ---
# value is optional
:> test.ini
crudini --set test.ini '' name
printf '%s\n' 'name = ' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# value is optional
printf '%s\n' 'name=val' > test.ini
crudini --set test.ini '' name
printf '%s\n' 'name=' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# --existing
:> test.ini
crudini --set test.ini '' gname val
crudini --set --existing test.ini '' gname val2
crudini --set --existing test.ini '' gname2 val 2>/dev/null && fail $LINENO
crudini --set test.ini section1 name val
crudini --set --existing test.ini section1 name val2
crudini --set --existing test.ini section1 name2 val 2>/dev/null && fail $LINENO
printf '%s\n' 'gname = val2' '' '' '[section1]' 'name = val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# missing
crudini --set missing.ini '' name val 2>/dev/null && fail $LINENO || ok $LINENO

# --get -------------------------------------------------

# ---
# basic get
test "$(crudini --get example.ini section1 cAps)" = 'not significant' && ok $LINENO || fail $LINENO

# ---
# get sections
crudini --get example.ini > test.ini
printf '%s\n' DEFAULT section1 'empty section' non-sh-compat > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# get implicit default section
crudini --get example.ini '' > test.ini
printf '%s\n' 'global' > good.ini
diff -u test.ini good.ini || fail $LINENO
crudini --format=ini --get example.ini '' > test.ini
printf '%s\n' '[DEFAULT]' 'global = supported' > good.ini
diff -u test.ini good.ini || fail $LINENO
ok $LINENO

# ---
# get explicit default section
crudini --get example.ini DEFAULT > test.ini
printf '%s\n' 'global' > good.ini
diff -u test.ini good.ini || fail $LINENO
crudini --get --format ini example.ini DEFAULT > test.ini
printf '%s\n' '[DEFAULT]' 'global = supported' > good.ini
diff -u test.ini good.ini || fail $LINENO
ok $LINENO

# ---
# get section1 in ini format
crudini --format=ini --get example.ini section1 > test.ini
diff -u test.ini section1.ini && ok $LINENO || fail $LINENO

# ---
# get section1 in sh format
crudini --format=sh --get example.ini section1 > test.ini
diff -u test.ini section1.sh && ok $LINENO || fail $LINENO

# ---
# empty DEFAULT is not printed
printf '%s\n' '[DEFAULT]' '#comment' '[section1]' > test.ini
test "$(crudini --get test.ini)" = 'section1' || fail $LINENO
printf '%s\n' '#comment' '[section1]' > test.ini
test "$(crudini --get test.ini)" = 'section1' || fail $LINENO
ok $LINENO

# ---
# missing bits
:> test.ini
crudini --get missing.ini 2>/dev/null && fail $LINENO
test "$(crudini --get test.ini)" = '' || fail $LINENO
crudini --get test.ini '' || fail $LINENO
crudini --get test.ini '' 'missing' 2>/dev/null && fail $LINENO
ok $LINENO

# --merge -----------------------------------------------

# ---
# XXX: An empty default section isn't merged
:> test.ini
printf '%s\n' '[DEFAULT]' '#comment' '[section1]' |
crudini --merge test.ini || fail $LINENO
printf '%s\n' '' '[section1]' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
:> test.ini
printf '%s\n' '[DEFAULT]' 'name=val' '[section1]' |
crudini --merge test.ini || fail $LINENO
printf '%s\n' '[DEFAULT]' 'name = val' '' '[section1]' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
:> test.ini
printf '%s\n' 'name=val' |
crudini --merge test.ini || fail $LINENO
printf '%s\n' 'name = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name = val2' |
crudini --merge test.ini || fail $LINENO
printf '%s\n' 'name=val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini || fail $LINENO
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'name = val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini '' || fail $LINENO
printf '%s\n' 'name = val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' '[DEFAULT]' 'name=val2' |
crudini --merge test.ini || fail $LINENO
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' '[DEFAULT]' 'name=val2' |
crudini --merge test.ini '' || fail $LINENO
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' '[DEFAULT]' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini '' || fail $LINENO
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini DEFAULT || fail $LINENO
printf '%s\n' '[DEFAULT]' 'name=val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge test.ini new || fail $LINENO
printf '%s\n' 'name=val1' '' '' '[new]' 'name = val2' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name=val2' |
crudini --merge --existing test.ini new 2>/dev/null && fail $LINENO || ok $LINENO

# ---
printf '%s\n' 'name=val1' > test.ini
printf '%s\n' 'name2=val2' |
crudini --merge --existing test.ini || fail $LINENO
printf '%s\n' 'name=val1' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
printf '%s\n' 'name=val1' '[section1]' 'name=val2' > test.ini
printf '%s\n' 'name=val1a' '[section1]' 'name=val2a' |
crudini --merge --existing test.ini || fail $LINENO
printf '%s\n' 'name=val1a' '[section1]' 'name=val2a' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
# All input sections merged to a specific section
printf '%s\n' 'name=val1' '[section1]' 'name=val2' > test.ini
printf '%s\n' 'name=val2a' '[section2]' 'name2=val' |
crudini --merge test.ini 'section1' || fail $LINENO
printf '%s\n' 'name=val1' '[section1]' 'name=val2a' 'name2 = val' > good.ini
diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# --del -------------------------------------------------

for sec in '' '[DEFAULT]'; do
# ---
  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini '' noname || fail $LINENO
  crudini --del --existing test.ini '' noname 2>/dev/null && fail $LINENO
  crudini --del test.ini '' name || fail $LINENO
  :> good.ini
  [ "$sec" ] && printf '%s\n' $sec > good.ini
  diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini 'DEFAULT' noname || fail $LINENO
  crudini --del --existing test.ini 'DEFAULT' noname 2>/dev/null && fail $LINENO
  crudini --del test.ini 'DEFAULT' name || fail $LINENO
  :> good.ini
  [ "$sec" ] && printf '%s\n' $sec > good.ini
  diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini nosect || fail $LINENO
  crudini --del --existing test.ini nosect 2>/dev/null && fail $LINENO
  crudini --del test.ini '' || fail $LINENO
  :> good.ini
  diff -u test.ini good.ini && ok $LINENO || fail $LINENO

# ---
  printf '%s\n' $sec 'name = val' > test.ini
  crudini --del test.ini nosect || fail $LINENO
  crudini --del --existing test.ini nosect 2>/dev/null && fail $LINENO
  crudini --del test.ini 'DEFAULT' || fail $LINENO
  :> good.ini
  diff -u test.ini good.ini && ok $LINENO || fail $LINENO
done

# --get-lines --------------------------------------------

# ---
crudini --get --format=lines example.ini section1 > test.ini || fail $LINENO
diff -u test.ini section1.lines && ok $LINENO || fail $LINENO

# ---
crudini --get --format=lines example.ini > test.ini || fail $LINENO
diff -u test.ini example.lines && ok $LINENO || fail $LINENO
