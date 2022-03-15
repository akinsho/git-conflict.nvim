#!/bin/bash
[ -d ./../conflict-test/ ] && rm -rf ./conflict-test/
mkdir conflict-test
cd conflict-test
git init
touch conflicted.lua
git add conflicted.lua
echo "local value = 1 + 1" > conflicted.lua
git commit -am 'initial'
git checkout -b new_branch
echo "local value = 1 - 1" > conflicted.lua
git commit -am 'first commit on new_branch'
git checkout main
cat > conflicted.lua<< EOF
local value = 5 + 7
print(value)
print(string.format("value is %d", value))
EOF
git commit -am 'second commit on main'
git merge new_branch
