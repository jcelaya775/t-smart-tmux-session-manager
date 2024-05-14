#!/usr/bin/env bash

# determine if the tmux server is running
if tmux list-sessions &>/dev/null; then
	TMUX_RUNNING=0
else
	TMUX_RUNNING=1
fi

# determine the user's current position relative tmux:
# serverless - there is no running tmux server
# attached   - the user is currently attached to the running tmux server
# detached   - the user is currently not attached to the running tmux server
T_RUNTYPE="serverless"
if [ "$TMUX_RUNNING" -eq 0 ]; then
	if [ "$TMUX" ]; then # inside tmux
		T_RUNTYPE="attached"
	else # outside tmux
		T_RUNTYPE="detached"
	fi
fi

# display help text with an argument
function display_help() {
	printf "\n"
	printf "\033[1m  t - the smart tmux session manager\033[0m\n"
	printf "\033[37m  https://github.com/joshmedeski/t-smart-tmux-session-manager\n"
	printf "\n"
	printf "\033[32m  Run interactive mode\n"
	printf "\033[34m      t\n"
	printf "\033[34m        ctrl-s list only tmux sessions\n"
	printf "\033[34m        ctrl-x list only zoxide results\n"
	printf "\033[34m        ctrl-f list results from the find command\n"
	printf "\n"
	printf "\033[32m  Go to session (matches tmux session, zoxide result, or directory)\n"
	printf "\033[34m      t {name}\n"
	printf "\n"
	printf "\033[32m  Open popup (while in tmux)\n"

	if [ "$TMUX_RUNNING" -eq 0 ]; then
		T_BIND=$(tmux show-option -gvq "@t-bind")
		if [ "$T_BIND" = "" ]; then
			T_BIND="T"
		fi
		printf "\033[34m      <prefix>+%s\n" "$T_BIND"
		printf "\033[34m        ctrl-s list only tmux sessions\n"
		printf "\033[34m        ctrl-x list only zoxide results\n"
		printf "\033[34m        ctrl-f list results from the find command\n"
	else
		printf "\033[34m      start tmux server to see bindings\n" "$T_BIND"
	fi

	printf "\n"
	printf "\033[32m  Clone a git repo and open it in a new session\n"
	printf "\033[34m      t -r [REPO_URL]\n"
	printf "\033[34m      t --repo [REPO_URL]\n"
	printf "\n"
	printf "\033[32m  Send a command to a new session before opening\n"
	printf "\033[34m      t -c [COMMAND]\n"
	printf "\033[34m      t --command [COMMAND]\n"
	printf "\n"
	printf "\033[32m  Show help\n"
	printf "\033[34m      t -h\n"
	printf "\033[34m      t --help\n"
	printf "\n"
	exit 0
}

HOME_REPLACER=""                                          # default to a noop
echo "$HOME" | grep -E "^[a-zA-Z0-9\-_/.@]+$" &>/dev/null # chars safe to use in sed
HOME_SED_SAFE=$?
if [ $HOME_SED_SAFE -eq 0 ]; then # $HOME should be safe to use in sed
	HOME_REPLACER="s|^$HOME/|~/|"
fi

get_fzf_prompt() {
	local fzf_prompt
	local fzf_default_prompt='>  '
	if [ "$TMUX_RUNNING" -eq 0 ]; then
		fzf_prompt="$(tmux show -gqv '@t-fzf-prompt')"
	fi
	[ -n "$fzf_prompt" ] && echo "$fzf_prompt" || echo "$fzf_default_prompt"
}
PROMPT=$(get_fzf_prompt)

get_fzf_find_binding() {
	local fzf_find_binding
	local fzf_find_binding_default='ctrl-f:change-prompt(find> )+reload(find ~ -maxdepth 3 -type d)'
	if [ "$TMUX_RUNNING" -eq 0 ]; then
		fzf_find_binding="$(tmux show -gqv '@t-fzf-find-binding')"
	fi
	[ -n "$fzf_find_binding" ] && echo "$fzf_find_binding" || echo "$fzf_find_binding_default"
}

FIND_BIND=$(get_fzf_find_binding)

get_sessions_by_mru() {
	tmux list-sessions \
		-F '#{session_last_attached} #{session_name}' \
		| sort --numeric-sort --reverse | awk '{print $2}; END {print "———"}'
}

get_zoxide_results() {
	zoxide query -l | sed -e "$HOME_REPLACER"
}

get_fzf_results() {
	if [ "$TMUX_RUNNING" -eq 0 ]; then
		fzf_default_results="$(tmux show -gqv '@t-fzf-default-results')"
		case $fzf_default_results in
		sessions)
			get_sessions_by_mru
			;;
		zoxide)
			get_zoxide_results
			;;
		*)
			get_sessions_by_mru && get_zoxide_results # default shows both
			;;
		esac
	else
		get_zoxide_results # only show zoxide results when outside tmux
	fi
}

function fzf_finder() {
  case $T_RUNTYPE in
    attached)
      if [[ -z $FZF_TMUX_OPTS ]]; then
        FZF_TMUX_OPTS="-p 53%,58%"
      fi

      RESULT=$(
      (get_fzf_results) | fzf-tmux \
        --bind "$FIND_BIND" \
        --bind "$SESSION_BIND" \
        --bind "$TAB_BIND" \
        --bind "$ZOXIDE_BIND" \
        --border-label "$BORDER_LABEL" \
        --header "$HEADER" \
        --no-sort \
        --prompt "$PROMPT" \
        "$FZF_TMUX_OPTS"
      )
      ;;
    detached)
      RESULT=$(
      (get_fzf_results) | fzf \
        --bind "$FIND_BIND" \
        --bind "$SESSION_BIND" \
        --bind "$TAB_BIND" \
        --bind "$ZOXIDE_BIND" \
        --border \
        --border-label "$BORDER_LABEL" \
        --header "$HEADER" \
        --no-sort \
        --prompt "$PROMPT"
      )
      ;;
    serverless)
      RESULT=$(
      (get_fzf_results) | fzf \
        --bind "$FIND_BIND" \
        --bind "$TAB_BIND" \
        --bind "$ZOXIDE_BIND" \
        --border \
        --border-label "$BORDER_LABEL" \
        --header " ^x zoxide ^f find" \
        --no-sort \
        --prompt "$PROMPT"
      )
      ;;
  esac
}

function query_zoxide_from_argument() {
  zoxide query "$1" &>/dev/null
  ZOXIDE_RESULT_EXIT_CODE=$?
  if [ $ZOXIDE_RESULT_EXIT_CODE -eq 0 ]; then # zoxide result found
    RESULT=$(zoxide query "$1")
  else # no zoxide result found
    ls "$1" &>/dev/null
    LS_EXIT_CODE=$?
    if [ $LS_EXIT_CODE -eq 0 ]; then # directory found
      RESULT=$1
    else # no directory found
      echo "No directory found for query \"$1\"."
      exit 1
    fi
  fi
}

function get_result_from_repo() {
  if [ -z "$2" ]; then
    echo "No repository url provided -r {url}"
    exit 1
  fi

  REPO_URL=$2
  if [[ $REPO_URL =~ \/([^\/]+)(\.git)?$ ]]; then
    REPO="${BASH_REMATCH[1]}" # doesn't exists for me
    if [[ -z $T_REPOS_DIR ]]; then
      echo "T_REPOS_DIR has not been set"
      exit 1
    fi
    cd "$T_REPOS_DIR" || exit
    git clone --recursive "$REPO_URL"
    RESULT=$(echo "$T_REPOS_DIR/$REPO" | sed 's/\.git$//')
  else
    echo "Invalid GitHub repository URL"
    exit 0
  fi
}

fzf_border_label_default=' t - smart tmux session manager '
BORDER_LABEL=${T_FZF_BORDER_LABEL:-$fzf_border_label_default}

HEADER=" ^s sessions ^x zoxide ^f find"
SESSION_BIND="ctrl-s:change-prompt(sessions> )+reload(tmux list-sessions -F '#S')"
ZOXIDE_BIND="ctrl-x:change-prompt(zoxide> )+reload(zoxide query -l | sed -e \"$HOME_REPLACER\")"
TAB_BIND="tab:down,btab:up"

QUERY_PROVIDED=false
REPO_PROVIDED=false
COMMAND=
while [ "$#" -gt 0 ]; do # process arguments
  case "$1" in
    -h|--help)
      display_help

      exit 0
      ;;
    -r|--repo)
      if [ "$REPO_PROVIDED" = true ]; then
        echo "Invalid number of arguments: \"$@\""
        echo "You can only use -r or --repo once."
        echo "Use -h or --help for more info."
        exit 1
      fi

      get_result_from_repo "$@"
      REPO_PROVIDED=true

      # shift to next flag
      shift
      shift
      ;;
    -c|--command)
      if [ "$COMMAND" != "" ]; then
        echo "Invalid number of arguments: \"$@\""
        echo "You can only use -c or --command once."
        echo "Use -h or --help for more info."
        exit 1
      fi

      COMMAND="$2"

      # shift to next flag
      shift
      shift
      ;;
    *) # zoxide query
      if [ "$QUERY_PROVIDED" = true ]; then
        echo "Invalid arguments: \"$@\""
        echo "If you are passing in a query with spaces, wrap it with quotes."
        echo "You cannot query zoxide and use -r or --repo at the same time."
        echo "Use -h or --help for more info."
        exit 1
      elif [ "$#" -gt 4 ] ; then
        echo "Invalid number of arguments: $@"
        echo "Use -h or --help for more info."
        exit 1
      fi

      query_zoxide_from_argument "$1"
      QUERY_PROVIDED=true

      # shift to next flag
      shift
      ;;
  esac
done

if [ "$QUERY_PROVIDED" = false ] && [ "$REPO_PROVIDED" = false ]; then # get query via fzf
    fzf_finder
fi

if [ "$RESULT" = "" ]; then # no result
	exit 0                     # exit silently
fi

if [ $HOME_SED_SAFE -eq 0 ]; then
	RESULT=$(echo "$RESULT" | sed -e "s|^~/|$HOME/|") # get real home path back
fi

zoxide add "$RESULT" &>/dev/null # add to zoxide database

if [[ $RESULT != /* ]]; then # not folder path from zoxide result
	SESSION_NAME=$RESULT
elif [[ $T_SESSION_USE_GIT_ROOT == 'true' ]]; then
	GIT_ROOT=$(git -C $RESULT rev-parse --show-toplevel 2>/dev/null) && echo $GIT_ROOT >/dev/null
	if [[ $? -ne 0 ]]; then # not inside git repository
		SESSION_NAME=$(basename "$RESULT" | tr ' .:' '_')
	else # is in git repository
		BASENAME=$(basename $GIT_ROOT)
		RELATIVE_PATH=${RESULT#$GIT_ROOT}

		# git worktree
		GIT_WORKTREE_ROOT=$(git -C $RESULT rev-parse --git-common-dir 2>/dev/null) && echo $GIT_WORKTREE_ROOT >/dev/null
		if [[ $? -eq 0 ]] && [[ ! $GIT_WORKTREE_ROOT =~ ^(\.\./)*\.git$ ]]; then # is inside git worktree
			GIT_WORKTREE_ROOT=$(echo $GIT_WORKTREE_ROOT | sed -E 's/(\/.git|\/.bare)$//') # remove .git or .bare suffix
			BASENAME=$(basename $GIT_WORKTREE_ROOT)
			RELATIVE_PATH=${RESULT#$GIT_WORKTREE_ROOT}
		fi

		SEPARATOR="/"
		FORMATTED_PATH="${RELATIVE_PATH//\//$SEPARATOR}"
		SESSION_NAME=$(echo $BASENAME$FORMATTED_PATH | tr ' .:' '_')
	fi
elif [[ $T_SESSION_NAME_INCLUDE_PARENT == 'true' ]]; then
	SESSION_NAME=$(echo "$RESULT" | tr ' .:' '_' | awk -F "/" '{print $(NF-1)"/"$NF}')
else
	SESSION_NAME=$(basename "$RESULT" | tr ' .:' '_')
fi

if [ "$T_RUNTYPE" != "serverless" ]; then
	SESSION=$(tmux list-sessions -F '#S' | grep "^$SESSION_NAME$") # find existing session
fi

if [ "$SESSION" = "" ]; then # session is missing
  SESSION="$SESSION_NAME"

  if [ -e "$RESULT/.t" ] && [ "$COMMAND" != "" ]; then # .t exists and command provided
    tmux new-session -d -s "$SESSION" -c "$RESULT"
    WINDOW_INFO=$(tmux list-window -t "$SESSION" | grep '(active)')
    SESSION_ACTIVE_WINDOW=$(echo "$WINDOW_INFO" | awk '{print $1}' | sed 's/://')
    tmux send-keys -t "$SESSION:$SESSION_ACTIVE_WINDOW" "$COMMAND && $RESULT/.t" Enter
  elif [ -e "$RESULT/.t" ]; then # .t exists and no command provided
    tmux new-session -d -s "$SESSION" -c "$RESULT"
    tmux send-keys -t "$SESSION:$SESSION_ACTIVE_WINDOW" "$RESULT/.t" Enter
  elif [ "$COMMAND" != "" ]; then # command provided and no .t
    tmux new-session -d -s "$SESSION" -c "$RESULT"
    WINDOW_INFO=$(tmux list-window -t "$SESSION" | grep '(active)')
    SESSION_ACTIVE_WINDOW=$(echo "$WINDOW_INFO" | awk '{print $1}' | sed 's/://')
    tmux send-keys -t "$SESSION:$SESSION_ACTIVE_WINDOW" "$COMMAND" Enter
  else # no .t or command provided
    tmux new-session -d -s "$SESSION" -c "$RESULT"
  fi
fi

case $T_RUNTYPE in # attach to session
attached)
	tmux switch-client -t "$SESSION"
	;;
detached | serverless)
	tmux attach -t "$SESSION"
	;;
esac
