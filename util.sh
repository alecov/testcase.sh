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
export -f jobpid

# extwait(): waits for several jobs:
#  All jobs in $waitall, $waitany, $waiterr and $@ are waited for.
#  If all jobs in $waitall finish, return the last failed exit status (or zero).
#  If any jobs in $waitany finish, return the last failed exit status (or zero).
#  If any job in $waiterr finishes, return 127.
#
#  If a finished job is in both $waitall and $waitany, return an error only if
#  the job finished with an error.
extwait() {
	waitall=($(jobpid "${waitall[@]}"))
	waitany=($(jobpid "${waitany[@]}"))
	waiterr=($(jobpid "${waiterr[@]}"))
	local index args=($(jobpid "$@"))
	declare -A alljobs=(); for index in \
		"${waitall[@]}" \
		"${waitany[@]}" \
		"${waiterr[@]}" \
		"${args[@]}"; do
		alljobs[$index]=1;
	done
	local result=0 waited wait; while true; do
		local waited_all=
		local waited_any=
		local waited_err=
		[[ -z ${waitall[@]} ]] && return $result
		wait=; wait -n "${!jobset[@]}" || wait=$?
		declare -A livejob=(); for index in $(jobs -p); do
			livejob[$index]=1
		done
		waited=; for index in ${!alljobs[@]}; do
			if [[ -z ${livejob[$index]} ]]; then
				waited=$index
				unset 'alljobs[index]'
			fi
		done
		[[ -z $waited ]] && return 127
		[[ -n $wait ]] && result=$wait
		for index in ${!args[@]}; do
			[[ ${args[index]} == $waited ]] && unset 'args[index]'
		done
		for index in ${!waitall[@]}; do if [[ ${waitall[index]} == $waited ]]; then
			waited_all=1
			unset 'waitall[index]'
		fi; done
		for index in ${!waitany[@]}; do if [[ ${waitany[index]} == $waited ]]; then
			waited_any=1
			unset 'waitany[index]'
		fi; done
		for index in ${!waiterr[@]}; do if [[ ${waiterr[index]} == $waited ]]; then
			waited_err=1
			unset 'waiterr[index]'
		fi; done
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
export -f extwait

# spawn_*(): spawns and controls a named parallel process.
#  These functions spawns a parallel process, redirecting output to logfiles
#  and adding their PIDs to the $wait* variables.
spawn_waitall() {
	local name=$1; shift
	"$@" >"$testlogdir"/"$name".out 2>"$testlogdir"/"$name".err &
	waitall+=($!)
}
spawn_waitany() {
	local name=$1; shift
	"$@" >"$testlogdir"/"$name".out 2>"$testlogdir"/"$name".err &
	waitany+=($!)
}
spawn_waiterr() {
	local name=$1; shift
	"$@" >"$testlogdir"/"$name".out 2>"$testlogdir"/"$name".err &
	waiterr+=($!)
}
export -f spawn_waitall
export -f spawn_waitany
export -f spawn_waiterr

# semwait(): waits for a semaphore fd (a pipe) and synchronizes with all
# processes listed for `extwait`.
#  To use a semaphore, create a pipe and connect it to an fd:
#    mkfifo "$tempdir"/sem
#    exec 3<>"$tempdir"/sem
semwait() {
	local count; for ((count=0; count < ${2:-1}; ++count)); do
		read -u${1:-3} & waitall+=($!) waitany+=($!); extwait
	done
}
export -f semwait
