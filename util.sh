# jobpid(): outputs jobs PIDs from jobspecs (%*).
#  Unrecognized jobs go unmolested. Not the same as `jobs -p`, since it treats
#  all arguments as jobspecs.
jobpid() {
	local arg; for arg; do
		[[ $arg == %* ]] &&
		jobs -p "$arg" 2>/dev/null ||
		printf %s\\n "$arg"
	done
}

# extwait(): waits for several jobs:
#  All jobs in $waitall, $waitany, $waiterr and $@ are waited for.
#  These are associative arrays used as sets.
#  If all jobs in $waitall finish, return the last failed exit status (or zero).
#  If any jobs in $waitany finish, return the last failed exit status (or zero).
#  If any job in $waiterr finishes, return 127.
#
#  If a finished job is in both $waitall and $waitany, return an error only if
#  the job finished with an error.

declare -A waitall=()
declare -A waitany=()
declare -A waiterr=()
extwait() {
	local job
	declare -A alljobs=()
	for job in "$@"; do
		job=$(jobpid "$job")
		alljobs[$job]=
	done
	for job in "${!waitall[@]}"; do
		unset 'waitall[$job]'
		job=$(jobpid "$job")
		waitall[$job]=
		alljobs[$job]=
	done
	for job in "${!waitany[@]}"; do
		unset 'waitany[$job]'
		job=$(jobpid "$job")
		waitany[$job]=
		alljobs[$job]=
	done
	for job in "${!waiterr[@]}"; do
		unset 'waiterr[$job]'
		job=$(jobpid "$job")
		waiterr[$job]=
		alljobs[$job]=
	done
	local result=0 waited wait=; while true; do
		local waited_all=
		local waited_any=
		local waited_err=
		declare -A livejobs=()
		[[ -z ${!waitall[@]} ]] && return $result
		wait=; wait -n "${!alljobs[@]}" || wait=$?
		for job in $(jobs -p); do livejobs[$job]=; done
		waited=; for job in ${!alljobs[@]}; do
			if [[ ! -v livejobs[$job] ]]; then
				waited=$job
				break
			fi
		done
		[[ -z $waited ]] && return 127
		[[ -n $wait ]] && result=$wait
		unset 'alljobs[$waited]'
		if [[ -v waitall[$waited] ]]; then
			unset 'waitall[$waited]'
			waited_all=1
		fi
		if [[ -v waitany[$waited] ]]; then
			unset 'waitany[$waited]'
			waited_any=1
		fi
		if [[ -v waiterr[$waited] ]]; then
			unset 'waiterr[$waited]'
			waited_err=1
		fi
		[[ -n $waited_err ]] && return 127
		if [[ -n $waited_any ]]; then
			if [[ -n $waited_all ]]; then
				[[ -n $wait ]] && return $wait
			else
				return $result
			fi
		fi
	done
}

# spawn_*(): spawns and controls a named parallel process.
#  These functions spawns a parallel process, redirecting output to logfiles
#  and adding their PIDs to the $wait* variables.
spawn_waitall() {
	local name=$1; shift
	"$@" >"$testlogdir"/"$name".out 2>"$testlogdir"/"$name".err &
	waitall[$!]=
}
spawn_waitany() {
	local name=$1; shift
	"$@" >"$testlogdir"/"$name".out 2>"$testlogdir"/"$name".err &
	waitany[$!]=
}
spawn_waiterr() {
	local name=$1; shift
	"$@" >"$testlogdir"/"$name".out 2>"$testlogdir"/"$name".err &
	waiterr[$!]=
}

# semwait(): waits for a semaphore fd (a pipe) and synchronizes with all
# processes listed for `extwait`.
#  To use a semaphore, create a pipe and connect it to an fd:
#    exec 3<> >(:)
semwait() {
	local count; for ((count=0; count < ${2:-1}; ++count)); do
		read -u${1:-3} & waitall[$!]= waitany[$!]=; extwait
	done
}
