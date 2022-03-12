#!/bin/bash
[ -d ./git-repo/ ] && rm -rf ./git-repo/
mkdir git-repo
cd git-repo
git init
touch test_code.lua
git add test_code.lua
echo "local value = 1 + 1" > test_code.lua
git commit -am 'initial'
git checkout -b new_branch
echo "local value = 1 - 1" > test_code.lua
git commit -am 'first commit on new_branch'
git checkout main
cat > test_code.lua<< EOF
local value = 5 + 7
print(value)
print(string.format("value is %d", value))
EOF
git commit -am 'second commit on main'
git merge new_branch
