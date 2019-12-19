
# This check makes sure bashrc is only loaded from Terminals > 1. Term1 should be reserved to load
# 'startx'. This makes sure e.g. PATH variables are not initialized twice.
if systemctl -q is-active graphical.target && [[ ! $DISPLAY && $XDG_VTNR -eq 1 ]]; then
  echo
  echo "... Environment not loaded. Use other terminal (ALT-F[2-6]) or 'startx' to load graphical environment ..."
  echo
else
  # Load bashrc
  if [[ -f $HOME/.bashrc ]]; then
	  source $HOME/.bashrc
  fi
fi

