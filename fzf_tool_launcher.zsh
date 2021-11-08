## INSTALLATION & REQUIREMENTS

# This file needs to be sourced into your zsh shell, and tmux needs
# to be running before you can use it.
# See the Readme.org file for details of use & configuration.
# LICENSE: GNU GPL V3 (http://www.gnu.org/licenses)
# Bitcoin donations gratefully accepted: 1AmWPmshr6i9gajMi1yqHgx7BYzpPKuzMz

function fzf-tool-menu() {
    [[ ${SHELL} =~ zsh ]] || { echo "This function only works with zsh"; return 1 }
    if [[ "${#}" -lt 1 || "${@[(I)-h|--help]}" -gt 0 ]]; then
	print "Usage: fzf-tool-menu <FILE>
Select program for processing file."
	return
    fi
    local toolsmenu 
    zstyle -s ':fzf-tool:' tools_menu_file toolsmenu || toolsmenu="${HOME}/.fzfrepl/tools_menu"
    # Commands for running tool in different types of window
    typeset -A windowcmds
    typeset cmdstr="{2..}"
    typeset kittycmd="eval \"kitty @launch --type XXX --env PAGER=${PAGER} --env LESS=${LESS} --env FZF_DEFAULT_OPTS=\${(q)FZF_DEFAULT_OPTS} --env FZFREPL_DEFAULT_OPTS=\${(q)FZFREPL_DEFAULT_OPTS} --env FZFREPL_DEFAULT_OPTS=\${(q)FZFREPL_DEFAULT_OPTS} \$(echo {2..})\""    
    windowcmds[kitty_tab]="${kittycmd//XXX/tab}"
    windowcmds[kitty_win]="${kittycmd//XXX/window}"
    windowcmds[tmux_win]="tmux new-window -n '$(basename ${1})' -d \"{2..}\""
    windowcmds[tmux_pane]="tmux split-window -d \"{2..}\""
    # Note: xterm command must be followed by & to allow file menu to still be usable after forking a tool menu
    windowcmds[xterm]="xterm -T '$(basename ${1})' -e \"{2..}\" &"
    windowcmds[eval]="eval {2..}"
    windowcmds[exec]="exec {2..}"
    typeset dfltwin win1 win2
    dfltwin=${FZFTOOL_WINDOW:-eval}
    if [[ -n ${TMUX} ]]; then
	win1=${FZFTOOL_WIN1:-tmux_win}
	win2=${FZFTOOL_WIN2:-tmux_pane}
    elif [[ ${TERM} == *kitty* ]]; then
	win1=${FZFTOOL_WIN1:-kitty_tab}
	win2=${FZFTOOL_WIN2:-kitty_win}
    elif [[ ${TERM} == *xterm* ]]; then
	win1=${FZFTOOL_WIN1:-xterm}
	win2=${FZFTOOL_WIN2:-xterm}
    else
	win1=${FZFTOOL_WIN1:-eval}
	win2=${FZFTOOL_WIN2:-eval}
    fi
    # Command for viewing the file formatted 
    typeset viewfile 
    typeset -a filetypes
    zstyle -g filetypes ':fzf-tool:previewcmd:'
    viewfile="${PAGER} ${1}"
    if [[ ${#filetypes} -gt 0 ]]; then
	local t tmp
        foreach t (${filetypes}) {
	    zstyle -s ':fzf-tool:previewcmd:' "${t}" tmp
	    if [[ "${1}" == *${t} ]]; then
		viewfile="${tmp//\{\}/${1}}|${PAGER}"
		break
	    fi
	}
    fi
    # Fit header to screen
    local header1="ctrl-g:quit|enter:run in ${dfltwin//eval/this window}|alt-1:run in ${win1}|alt-2:run in ${win2}|ctrl-v:view raw file|alt-v:view formatted file"
    local header2 i1=0 ncols=$((COLUMNS-5))
    local i2=${ncols}
    until ((i2>${#header1})); do
	i2=${${header1[${i1:-0},${i2}]}[(I)|]}
	header2+="${header1[${i1},((i1+i2-1))]}
"
	i1=$((i1+i2+1))
	i2=$((i1+ncols))
    done
    header2+=${header1[$i1,$i2]}
    # Feed tools menu to fzf
    sed -e '/#/d;/^\s*\$/d' -e "s*{}*${1}*g" "${toolsmenu}"| \
    	fzf --with-nth=1 --preview-window=down:3:wrap \
	    --height=100% \
	    --header="${header2}" \
    	    --preview='echo {2..}' \
    	    --bind="alt-v:execute(${viewfile} >&2)" \
	    --bind="ctrl-v:execute(${PAGER} ${1} >&2)" \
	    --bind="alt-1:execute(${windowcmds[${win1}]})" \
    	    --bind="alt-2:execute(${windowcmds[${win2}]})" \
    	    --bind="enter:execute(${windowcmds[${dfltwin}]})"
}

function fzf-tool-files() {
    [[ ${SHELL} =~ zsh ]] || { echo "This function only works with zsh"; return 1 }
    if [[ "${#}" -lt 1 || "${@[(I)-h|--help]}" -gt 0 ]]; then
	print "Usage: fzf-tool-files <FILES>...
Preview & select file(s) to be processed, and program(s) to do the processing."
	return
    fi
    typeset preview maxsize 
    typeset -a filetypes
    zstyle -g filetypes ':fzf-tool:previewcmd:'
    zstyle -s ':fzf-tool:' max_preview_size maxsize || maxsize=10000000
    local condstr="[ \$(stat -c '%s' {}) -gt ${maxsize} ]"
    if [[ ${#filetypes} -gt 0 ]]; then
	preview='f={} && if'
	local t tmp
        foreach t (${filetypes}) {
	    zstyle -s ':fzf-tool:previewcmd:' "${t}" tmp
	    preview+=" [ -z \"\${f%%*${t}}\" ];then ${tmp};elif"
	    preview+=" [ -z \"\${f%%*${t:u}}\" ];then ${tmp};elif"
	    preview+=" [ -z \"\${f%%*${(C)t}}\" ];then ${tmp};elif"
	}
	preview="if ${condstr};then head -c${maxsize} {};echo \"\n\nTRUNCATED TO FIRST ${maxsize} BYTES\";else {${preview%%elif}else cat {};fi||cat {}};fi"
    else
	preview="cat {}"
    fi
    # TODO: try to get {+} replacements working. Have tried all different kinds of quoting combinations, but none seem to work.
    # The substitution works for the --preview option, but not the --bind option. To get it to work for the --preview option
    # you have to quote the {+} replacement in the sed command, otherwise it introduces spaces which makes sed think the command
    # is incomplete. However, when I try the same thing with the --bind command it doesn't work; fzf emits an "unknown action" error,
    # followed by the text right after the +. fzf treats the + as an action separator (used for chaining commnds, see the docs).
    # Also $tools doesn't work if {} (the selected filename) contains spaces due to same reasons stated above.
    #tools="sed '/#/d;/^\s*\$/d' ${toolsmenu}|fzf --with-nth=1 --preview-window=down:3:wrap --preview='echo \{2..}|sed -e s@\{\}@{}@g -e s@\{\+\}@\"{+}\"@g' --bind='enter:execute(tmux new-window -n test -d \"\$(echo \{2..}|sed -e s@\{\}@{}@g)\")'"

    # NOTE: TRY $'' quoting to fix problem noted above, also maybe setting RC_QUOTES might help?

    # TODO: either in this function, or in fzfrepl, add keybinding to pipe output to new/existing tool window
    #       imagine having different frames in the same window all working on the same initial file...

    # Fit header to fit screen
    local header1="ctrl-g:quit|enter:tools menu|ctrl-j:print filename|ctrl-v:view raw|alt-v:view formatted"
    local header2 i1=0 ncols=$((COLUMNS-5))
    local i2=${ncols}
    until ((i2>${#header1})); do
	i2=${${header1[${i1:-0},${i2}]}[(I)|]}
	header2+="${header1[${i1},((i1+i2-1))]}
"
	i1=$((i1+i2+1))
	i2=$((i1+ncols))
    done
    header2+=${header1[$i1,$i2]}
    # Feed input to fzf
    local file=$(print -l ${@}|fzf --height=100% \
				   --header="${header2}" \
				   --preview="stat -c 'SIZE:%s bytes OWNER:%U GROUP:%G PERMS:%A' {} && ${preview}" \
				   --bind="ctrl-v:execute(${PAGER} {} >&2)" \
				   --bind="alt-v:execute({${preview}}|${PAGER} >&2)" \
				   --bind="ctrl-j:accept" \
				   --bind="enter:execute(source ${funcsourcetrace%%:[0-9]##} && fzf-tool-menu {})")
    local -a lines
    lines=("${(@f)file}")
    print ${lines[-1]}
}
