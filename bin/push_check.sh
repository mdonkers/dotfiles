#!/bin/bash

dateStart=$(date +"%s")

echo

for DIR in $(find . -type d -maxdepth 1 -mindepth 1) ; do
  # Subshell because we cd
  (
  cd "${DIR}"
  if [[ -d ".git" ]]
  then
    if [[ -n "$(git log --branches --not --remotes --simplify-by-decoration --decorate --oneline 2> /dev/null)" ]]; then
      echo "GIT - unpushed changes! ; "
      pwd
      echo
    fi 
  fi
  )
done

echo

dateEnd=$(date +"%s")
diff=$(($dateEnd-$dateStart))
echo "$(($diff / 60)) minutes and $(($diff % 60)) seconds elapsed."
