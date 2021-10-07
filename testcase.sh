@() {
local -; set -e
BS() { :; }; export -f BS
if [[ $color == 1 || $color != 0 && -t 1 && -t 2 ]]; then
	[[ ! -v RS ]] && export RS=$(tput sgr0)
	[[ ! -v BF ]] && export BF=$(tput bold)
	[[ ! -v F1 ]] && export F1=$(tput setaf 1)
	[[ ! -v F2 ]] && export F2=$(tput setaf 2)
	[[ ! -v F3 ]] && export F3=$(tput setaf 3)
	[[ ! -v F4 ]] && export F4=$(tput setaf 4)
	[[ ! -v F5 ]] && export F5=$(tput setaf 5)
	[[ ! -v F6 ]] && export F6=$(tput setaf 6)
	[[ ! -v F7 ]] && export F7=$(tput setaf 7)
	[[ ! -v B1 ]] && export B1=$(tput setab 1)
	[[ ! -v B2 ]] && export B2=$(tput setab 2)
	[[ ! -v B3 ]] && export B3=$(tput setab 3)
	[[ ! -v B4 ]] && export B4=$(tput setab 4)
	[[ ! -v B5 ]] && export B5=$(tput setab 5)
	[[ ! -v B6 ]] && export B6=$(tput setab 6)
	[[ ! -v B7 ]] && export B7=$(tput setab 7)
	BS() { tput cub ${1:-1}; }
else
	spinner=0
fi

selfdir=$(realpath "$BASH_SOURCE")
selfdir=${selfdir%/*}
source=${BASH_SOURCE[-1]}
if [[ -z $srcname ]]; then
	srcname=$source
	srcname=${srcname##*/}
	srcname=${srcname%%.*}
fi

: ${srcdesc:=${srcname}}
: ${testlist:=${1:-*}}
: ${timeout:=inf}
: ${logdir:=log}
: ${logext:=log}
: ${kill:=KILL}

export logdir
export logext
[[ $logdir != */ ]] && logdir=$logdir/
[[ $logext != .* ]] && logext=.$logext
[[ -z $spinner && ( ! -t 1 || ! -t 2 ) ]] && spinner=0

cat <<-::
	${BF}${F2}$srcdesc${RS}${BF} test script${RS}
::

is_docker() { grep -q /docker/ /proc/1/cgroup; }
if [[ $unshare != 0 ]] && ! unshare -Upf --mount-proc true; then
	is_docker || cat <<-:: >&2
		Your system is missing the necessary setup for unshare(1).
		If you are running a Debian derivative, you need to allow
		unprivileged user namespaces by running as root:

		﻿	sysctl kernel.unprivileged_userns_clone=1

	::
	[[ $unshare == force ]] && exit 1 || unshare=0
	echo -e "Tests will continue without namespace isolation.\n" >&2
fi

if
	[[ $perf != 0 ]] && ! perf record -o/dev/null true 2>/dev/null &&
	[[ $(sysctl -n kernel.perf_event_mlock_kb) < 1073741824 ]];
then
	cat <<-:: >&2
		Your system is missing the necessary setup for perf(1).
		The following must be run as root to allow non-root users to
		inspect performance counters reliably:

		﻿	sysctl kernel.perf_event_paranoid=0
		﻿	sysctl kernel.perf_event_mlock_kb=1073741824

		You also need linux-perf installed in your system.

	::
	[[ $perf == force ]] && exit 1 || perf=0
	echo -e "Tests will continue without performance analysis.\n" >&2
fi

[[ $perf != 0 ]] &&
{ perf record $perfargs -qo/dev/null true ||
{ perfargs=-m256; perf record $perfargs -qo/dev/null true; } } 2>/dev/null &&
monitor() { perf record $perfargs -o"$testlogdir"/"$(basename "$1")".perf -- "$@"; } ||
{ monitor() { time "$@"; }; perf=0; }
export -f monitor

trap 'set +e; exec &>/dev/null; kill -- $(jobs -p); wait; rm -rf "$tempdir"' EXIT
export tempdir="$(mktemp -d)"
export unshare perf perfargs
declare -Ag testcase_count

testcase() {
	export testname=${1:-$srcname-$((++testcase_count))}; shift
	[[ $testname != $testlist ]] && return
	export testlogdir=$logdir$testname/
	export testlog=$logdir$testname$logext
	rm -rf "$testlogdir" "$testlog"; (
	local logcatout=
	local logcaterr=
	local logcatlog=
	cleanup() {
		set +e; exec 2>/dev/null
		[[ -z $logcatout ]] && head -vn-0 "$testlogdir"/*.out >>"$testlog"
		[[ -z $logcaterr ]] && head -vn-0 "$testlogdir"/*.err >>"$testlog"
		[[ -z $logcatlog ]] && head -vn-0 "$testlogdir"/*.log >>"$testlog"
		rmdir -p "$testlogdir"
		kill -"$kill" -- $(jobs -p); wait
		echo -n ${RS}
	}
	trap cleanup EXIT
	mkdir -p "$testlogdir"
	echo -n "${BF}${F1}•${RS}${BF} Running testcase \"${F6}$testname${RS}${BF}\"...   "
	[[ $spinner != 0 ]] && while true; do
		echo -n "$(BS 2)◴ "; sleep 0.25; echo -n "$(BS 2)◷ "; sleep 0.25
		echo -n "$(BS 2)◶ "; sleep 0.25; echo -n "$(BS 2)◵ "; sleep 0.25
	done &
	exec {fd}<> >(:)
	{ echo "source ${selfdir@Q}/util.sh"; cat; echo extwait; } >&$fd
	eval exec $fd\</dev/fd/\$fd
	local result=0
	local command=(timeout --foreground "$timeout" bash -c
	"set -m; trap 'kill -${kill@Q} -- -\$!' EXIT; bash -e /dev/fd/$fd & exec &>/dev/null; wait %1")
	[[ $unshare != 0 ]] && command=(unshare -Upf --mount-proc "${command[@]}")
	set -m; "${command[@]}" "$@" &>"$testlog" || result=$?; set +m
	{ kill %1; wait %1; } 2>/dev/null || true; echo -n "$(BS 6): "
	head -vn-0 "$testlogdir"/*.out >>"$testlog" 2>/dev/null || true; logcatout=1
	head -vn-0 "$testlogdir"/*.err >>"$testlog" 2>/dev/null || true; logcaterr=1
	head -vn-0 "$testlogdir"/*.log >>"$testlog" 2>/dev/null || true; logcatlog=1
	case $result in
		130) echo ${F3}canceled${RS};;
		124) echo ${F3}timeout${RS};;
		0) echo ${F2}success${RS};;
		*)
			if [[ $result -ge 127 ]]; then
				echo "${F5}killed (SIG$(kill -l $((result-127))))${RS}"
			else
				echo ${F1}failure${RS}
			fi;;
	esac
	if [[ $result -ne 0 ]]; then
		echo "  Log file: $(realpath "$testlog")"
		if [[ $fulldump == 1 ]]; then
			echo "  Full output:"
			sed 's/^/·	/' "$testlog"
		else
			echo "  Tail output:"
			tail -n"${taildump:-10}" "$testlog" | sed 's/^/·	/'
		fi
	fi
	exit $result
)}
}; @ "$@"
