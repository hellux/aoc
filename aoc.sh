#!/bin/sh

die() {
    printf "error: " >&2
    printf "%s\n" "$@" >&2
    rm -rf "$tmp"
    exit 1
}

c_start_year=2015
c_start_day=1
c_end_day=25

c_url_base="https://adventofcode.com"

c_exec_name=solution
c_user_agent_auth="user-agent: Mozilla/5.0 (X11; Linux x86_64; rv:68.0) Gecko/20100101 Firefox/68.0"
c_user_agent="User-Agent:github.com/hellux/aoc by noah@hllmn.net"
c_html_dump="elinks -no-numbering -no-references -dump -dump-color-mode 1"

path_obj() { printf "%s/puzzles/aoc_%d-%02d_%s" "$cache" "$year" "$day" "$1"; }
path_solution() { printf "%d/day%02d_%s" "$year" "$day" "$1"; }

c_obj_ans="answer"
c_obj_input="input"
c_obj_desc="desc"
c_obj_ex="ex"

aoc=$(basename "$0")

c_commands=$(cat <<eof
commands:
    init        initialize solutions directory
    select      save current selection of year and day
    status      show selection, login and completion status
    auth        authenticate user and create session cookie
    fetch       fetch objects, e.g. puzzle description or input
    view        view an object, e.g. puzzle description or input
    edit        open the puzzle solution in a text editor
    run         compile and execute solution
    submit      submit answer for puzzle
    clean       delete all build files, fetched items, cookies
    help        show info about commands
eof
)

c_usage=$(cat <<eof
usage: $aoc [-y YEAR] [-d DAY] <command> [<command option>]

global options:
    -y YEAR     temporarily select year
    -d DAY      temporarily select day

Year and day specified as options will be used for the current command but will
not alter the current selection (use select command for that).

$c_commands
eof
)

c_objects=$(cat <<eof
objects:
    desc        puzzle description
    input       puzzle input
eof
)

request() {
    url="$1"
    shift 1

    code=$(curl -L -s -b "$cache/jar" -o "$tmp/request" -w '%{http_code}' \
           -H "$c_user_agent" \
           "$@" "$url")

    [ "$code" != "200" ] && die "HTTP request to '$url' failed. -- code $code"

    cat "$tmp/request"
}

completed_part() {
    if [ -r "$cache/user" ]; then
        [ -r "$cache/completed_$year" ] || status_cmd -s days > /dev/null
        printf "%d" "$(sed -n "${day}p" "$cache/completed_$year")"
    else
        echo 0
    fi
}

ts_entry() { printf "%d-%02d-%s" "$year" "${2:-$day}" "$1"; }
ts_write() {
    ts_read "$1" >/dev/null \
        || echo "$(ts_entry "$1" "$2"):$(date +%s)" >> "$cache/timestamps"
}
ts_read() {
    [ "$1" -ge 0 ] 2>/dev/null && echo "$1" && return
    [ "$1" = "now" ] && date +%s && return
    [ "$1" = "unlock" ] && date -d "$year-12-${2:-$day} EST" +%s && return
    ts_e=
    [ -r "$cache/timestamps" ] && ts_e=$(grep -E "^$(ts_entry "$1" "$2")" "$cache/timestamps")
    [ -n "$ts_e" ] && echo "${ts_e##*:}"
}
ts_diff() {
    ts_a=$(ts_read "$1" "$3")
    [ -z "$ts_a" ] && return
    ts_b=$(ts_read "$2" "$3")
    [ -z "$ts_b" ] && return
    ts_d=$((ts_b-ts_a))
    if [ "$ts_d" -gt 86400 ]; then
        echo ">24h"
    else
        ts_h=$((ts_d/3600))
        ts_d=$((ts_d%3600))
        ts_m=$((ts_d/60))
        ts_s=$((ts_d%60))
        printf "%02d:%02d:%02d\n" "$ts_h" "$ts_m" "$ts_s"
    fi
}

c_usage_init="usage: $aoc init"

init_cmd() {
    [ -n "$*" ] && die "trailing args -- $*"
    [ -d "$cache" ] && die "cache already exists at '$cache'"
    mkdir -p "$cache" && echo "cache: $cache" >&2
    if [ ! -r Makefile ]; then
        makefile=$(dirname "$(realpath "$aoc")")/Makefile
        [ -r "$makefile" ] || die "'$makefile' does not exist"
        ln -s "$makefile" Makefile && echo "Makefile -> $makefile" >&2
    fi
    echo
    echo "use $aoc auth to sign in" >&2
}

c_usage_select=$(cat <<eof
usage: $aoc [-y YEAR] [-d DAY] select [<year>|<day>|<command>]..

Set the currently selected puzzle that will be used for subsequent commands.

commands:
    [t]oday     select today's puzzle
    [n]ext      select next puzzle
    [p]rev      select previous puzzle
eof
)

select_cmd() {
    for input in "$@"; do
        case "$input" in
            t|today)
                year=$(date +"%Y")
                day=$(date +"%e");;
            n|next)
                if [ "$day" -eq "$c_end_day" ];
                then year=$((year+1)); day="$c_start_day"
                else day=$((day+1));
                fi;;
            p|prev)
                if [ "$day" -eq "$c_start_day" ];
                then year=$((year-1)); day="$c_end_day"
                else day=$((day-1));
                fi;;
            [1-9]|1[0-9]|2[0-5]) day="$input";;
            20[0-9][0-9]) year="$input";;
            *) die "invalid selection -- $input" "$c_usage_select"
        esac
    done

    # Update selections cache
    echo "$year" > "$cache/year"
    echo "$day"  > "$cache/day"

    printf "[ %d - day %02d ] set as current selection.\n" "$year" "$day"
}

c_usage_status=$(cat <<eof
"usage: $aoc [-y YEAR] [-d DAY] status [-s] [-v] [<command>]

options:
    -s              synchronize, update cache
    -v              verbose output, depends on command

commands:
    events          events with current completion
    days            days with current completion
    stats           personal leaderboard times
    leaderboard     show private leaderboards
    login           current login status
eof
)

status_cmd() {
    sync=false
    OPTIND=1
    while getopts s flag; do
        case "$flag" in
            s) sync=true;;
            *) die "invalid flag" "$c_usage_status"
        esac
    done
    shift $((OPTIND-1))

    cmd=$1
    if [ -z "$cmd" ]
    then cmd=days
    else shift 1
    fi

    [ -n "$*" ] && die "trailing args -- $*"

    case "$cmd" in
        events)
            [ -r "$cache/user" ] || die "not signed in"

            if [ "$sync" = true ] || [ ! -r "$cache/events" ]; then
                # Get available events
                request "$c_url_base/$c_start_year/events" > "$tmp/events"
                grep -oE '\[[0-9]{4}\]' "$tmp/events" \
                    | sed 's/\[//;s/\]//' \
                    | sed '1!G;h;$!d' \
                    > "$cache/events"

                # Get number of completed stars for each event
                if [ -r "$cache/jar" ]; then
                    tmp_year=$year
                    while read -r year; do
                        status_cmd -s days > /dev/null
                    done < "$cache/events"
                    year=$tmp_year
                fi
            fi

            user=$(cat "$cache/user")

            echo "Event completion for [$user]:"
            echo '-----------------------------'
            printf "Year\tGolden\tSilver\tTotal\n"
            while read -r y; do
                f="$cache/completed_$y"
                printf "%d" "$y"
                if [ -r "$f" ]; then
                    golden=$(grep -c "2" "$f")
                    silver=$(grep -c "1" "$f")
                    total=$((golden*2 + silver))
                    printf "\t%d\t%d\t%d" "$golden" "$silver" "$total"
                else
                    printf "\t-\t-\t-"
                fi
                echo
            done < "$cache/events"
            ;;
        days)
            [ -r "$cache/user" ] || die "not signed in"

            user=$(cat "$cache/user")

            if [ "$sync" = true ] || [ ! -r "$cache/completed_$year" ]; then
                request "$c_url_base/$year" > "$tmp/year"

                for _ in $(seq "$c_end_day"); do echo 0; done > "$tmp/zeroes"
                awk 'BEGIN { RS="<"; FS="=" }
                     $1 == "a aria-label" { printf "%s\n", $2 }' \
                    "$tmp/year" \
                    | rev | cut -c6- | rev | tr -d '"' \
                    | sort -nk2 \
                    | sed 's/.*two stars.*/2/;s/.*one star.*/1/;s/Day.*/0/' \
                    | paste "$tmp/zeroes" - | tr -d '\t' \
                    | sed 's/02/2/;s/01/1/' \
                    > "$cache/completed_$year"
            fi

            day=1
            echo "$year completion for [$user]:"
            echo '-------------------------------------'
            printf "Day\tStars\tTitle (solution name)\n"
            while read -r comp; do
                desc_path=$(path_obj "$c_obj_desc")
                if [ -r "$desc_path" ]; then
                    puzzle_title="$(grep '<article' "$desc_path" \
                            | awk 'BEGIN {FS="---"; RS=":"} NR==2 {print $1}' \
                            | xargs \
                            | sed "s/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/\</g;
                                   s/&gt;/\>/g; s/&quot;/\"/g; s/&ldquo;/\"/g;
                                   s/&rdquo;/\"/g; s/&apos;/'/g;") "
                else
                    puzzle_title=""
                fi

                    day_dir="$(echo "$(path_solution "")"*)"
                if [ -r "$day_dir" ];
                then dirname="($(basename "$day_dir" | cut -c 7-))"
                else dirname=""
                fi

                title="$puzzle_title$dirname"

                if [ "$comp" -eq 1 ]; then stars="*"
                elif [ "$comp" -eq 2 ]; then stars="**"
                else stars=""
                fi

                if [ "$day" -eq "$cached_day" ] && [ "$year" -eq "$cached_year" ];
                then day_str="[$day]"
                else day_str=" $day"
                fi

                printf '%s\t%s\t%s\n' "$day_str" "$stars" "$title"

                day=$((day+1))
            done < "$cache/completed_$year"
            ;;
        stats)
            [ -r "$cache/user" ] || die "not signed in"

            user=$(cat "$cache/user")

            if [ "$sync" = true ] || [ ! -r "$cache/stats_$year" ]; then
                request "$c_url_base/$year/leaderboard/self" > "$tmp/stats"

                beg=$(awk '/<pre>/ {print NR; exit}' "$tmp/stats")
                end=$(awk '/<\/pre>/ {print NR}' "$tmp/stats" | tail -n1)
                tail -n +"$beg" "$tmp/stats" | head -n $((end-beg+1)) \
                    | sed 's/^.*<pre>/<pre>/' \
                    > "$cache/stats_$year"
            fi

            $c_html_dump "$cache/stats_$year" | cat
            ;;
        leaderboard)
            [ -r "$cache/user" ] || die "not signed in"

            if [ "$sync" = "true" ] || [ ! -d "$cache/lb_priv/$year" ]; then
                request "$c_url_base/$year/leaderboard/private" \
                    | grep -Eo "leaderboard/private/view/[0-9]+" \
                    | while read -r lb; do
                        mkdir -p "$cache/lb_priv/$year"
                        request "$c_url_base/$year/$lb.json" > "$cache/lb_priv/$year/${lb##*/}"
                    done
            fi

            for lb in "$cache"/lb_priv/"$year"/*; do
                for d in $(seq 25); do
                    for p in $(seq 2); do
                        out=$(< "$lb" jq -r '.members
                            | [to_entries[].value][]
                            | .name as $name
                            | .completion_day_level."'"$d"'"."'"$p"'"
                            | select (.)
                            | [.get_star_ts, $name]
                            | @tsv' \
                            | sort | while IFS=$(printf "\t") read -r t n; do
                            printf "%s\t%s\t%s\n" "$(ts_diff unlock "$t" "$d")" "$n"
                        done
                        )
                        [ -n "$out" ] && echo "Day $d part $p" && echo "$out" && echo
                    done
                done

                echo "                  1111111111222222"
                echo "         1234567890123456789012345"
                < "$lb" jq -r '.members
                    | [to_entries[].value]
                    | sort_by(.local_score)
                    | reverse[]
                    | [
                        .name,
                        .local_score,
                        if .last_star_ts > 0
                            then (.last_star_ts | localtime | strftime("%F %R:%S"))
                            else "-"
                        end,
                        (.completion_day_level as $comp
                            | range(1;26)
                            | $comp.[(tostring | tostring)]
                            | length)
                    ] | @tsv' | while IFS=$(printf "\t") read -r name score ts days; do
                    printf "%8s " "$score"
                    for d in $days; do
                        case $d in
                            0) printf " ";;
                            1) printf ".";;
                            2) printf "*";;
                        esac
                    done
                    printf " %-19s %s\n" "$ts" "$name"
                done
                echo
            done
            ;;
        login)
            if [ -r "$cache/jar" ]; then
                if [ "$sync" = true ]; then
                    request "$c_url_base/$c_start_year/events" > "$tmp/events"
                    if grep "Log In" "$tmp/events"; then
                        echo "Logic session expired."
                    else
                        awk 'BEGIN { RS="<"; FS=">" }
                             $1 == "div class=\"user\"" { printf "%s\n", $2 }' \
                            "$tmp/events" \
                            | tr -d " " > "$cache/user"
                    fi
                fi

                echo "Logged in as $(cat "$cache/user")."
            else
                echo "Logged out."
            fi
            ;;
        *) die "invalid command -- $cmd" "$c_usage_status";;
    esac
}

c_usage_auth=$(cat <<eof
usage: $aoc auth <service>

Sign in to a service and create a session cookie that will be used for
subsequent commands.

services:
    reddit
eof
)

auth_cmd() {
    service="$1"
    [ -z "$service" ] && die "no service specified" "$c_usage_auth"
    shift 1

    [ -n "$*" ] && die "trailing args -- $*"

    case "$service" in
        reddit) auth_reddit;;
        *) die "unimplemented service -- $service" "$c_usage_auth";;
    esac
}

auth_reddit() {
    # Get credentials from user.
    printf "reddit username: "
    read -r username
    stty -echo
    printf "password: "
    read -r password
    stty echo
    printf "\n"

    rm -f "$cache/jar"

    echo "Fetching CSRF token, reddit login session cookie..."
    csrf=$(request "https://www.reddit.com/login/" -c "$cache/jar" | \
           grep 'csrf_token' | \
           grep -Eo "[0-9a-z]{40}")

    echo "Signing in to reddit..."
    LOGIN_PARAMS="username=$username&password=$password&csrf_token=$csrf"
    code=$(curl -s -H "$c_user_agent_auth" --data "$LOGIN_PARAMS" \
                -b "$cache/jar" -c "$cache/jar" \
                -o /dev/null -w '%{http_code}' \
                "https://www.reddit.com/login" \
           || exit 1)
    if [ "$code" -eq 400 ]; then
        echo "invalid password"
        rm -f "$cache/jar"
        exit 1
    fi

    echo "Fetching uh token..."
    uh=$(curl -s -H "$c_user_agent_auth" \
              -b "$cache/jar" \
              -L "$c_url_base/auth/reddit" | \
         grep -Eo "[0-9a-z]{50}" | \
         head -n1 \
         || exit 1)

    echo "Authorizing application..."
    c_auth="client_id=macQY9D1vLELaw&duration=temporary&redirect_uri=https://adventofcode.com/auth/reddit/callback&response_type=code&scope=identity&state=x&uh=$uh&authorize=Accept"
    curl -s --data "$c_auth" \
         -H "$c_user_agent_auth" \
         -b "$cache/jar" -c "$cache/jar" \
         -L "https://www.reddit.com/api/v1/authorize" > /dev/null

    # Keep only the needed session cookie.
    sed -i -n '/adventofcode.com/p' "$cache/jar"

    status_cmd -s login
}

c_usage_fetch=$(cat <<eof
usage: $aoc [-y YEAR] [-d DAY] fetch <object>..

Fetch objects and store them in the cache.

$c_objects
eof
)

fetch_cmd() {
    [ -z "$*" ] && die "no object specified" "$c_usage_fetch"

    while :; do
        [ "$(($(ts_read unlock)-$(ts_read now)))" -le 0 ] && break
        printf "\rPuzzle for day %d, %d unlocks in %s." \
            "$day" "$year" "$(ts_diff now unlock)" >&2
        sleep 1
    done

    for object in "$@"; do
        url=""
        needs_auth=false
        case "$object" in
            "$c_obj_input")
                url="$c_url_base/$year/day/$day/input";
                needs_auth=true;;
            "$c_obj_desc")
                url="$c_url_base/$year/day/$day";;
            *) die "invalid fetch object -- $object";;
        esac

        [ "$needs_auth" = "true" ] && [ ! -r "$cache/jar" ] && die "not signed in"

        echo "Fetching $year day $day $object..."
        request "$url" > "$tmp/object"

        output_path="$(path_obj "$object")"
        mkdir -p "$(dirname "$output_path")"
        cp "$tmp/object" "$(path_obj "$object")"
    done
}

c_usage_view=$(cat <<eof
usage: $aoc view [<option>].. desc
       $aoc view [<option>].. input
       $aoc view [<option>].. ex [<num>]

View an object with 'less' or a specified command.

options:
    -c          provide command to view object with
eof
)

view_cmd() {
    viewer="less -rf"
    OPTIND=1
    while getopts c: flag; do
        case "$flag" in
            c) viewer="$OPTARG";;
            *) die "invalid flag" "$c_usage_view"
        esac
    done
    shift $((OPTIND-1))

    view_object=$1
    [ -z "$view_object" ] && die "no object specified" "$c_usage_view"
    shift 1

    if [ "$view_object" = "$c_obj_ex" ]; then
        fetch_object="$c_obj_desc"
        exnums="$*"
        shift $#
    else
        fetch_object="$view_object"
    fi
    [ -n "$*" ] && die "trailing arguments -- $*"

    object_path=$(path_obj "$fetch_object")
    fetch=false
    if [ ! -r "$object_path" ]; then
        # Fetch if non-existent
        fetch=true
    elif [ "$fetch_object" = "$c_obj_desc" ]; then
        # Fetch if second part available
        p1_completed=false
        p2_downloaded=false

        [ "$(completed_part)" -ge 1 ] && p1_completed=true
        [ "$(grep -c '<article' "$object_path")" -eq 2 ] \
            && p2_downloaded=true
        if [ "$p1_completed" = true ] && [ "$p2_downloaded" != true ]
        then fetch=true
        fi
    fi

    [ "$fetch" = "true" ] && fetch_cmd "$fetch_object"

    case "$view_object" in
        "$c_obj_desc")
            beg=$(awk '/<article/ {print FNR; exit}' "$object_path")
            end=$(awk '/>get your puzzle input</ {print FNR}' "$object_path" | tail -n1)
            tail -n +"$beg" "$object_path" | head -n $((end-beg+1)) \
                | $c_html_dump > "$tmp/view"

            part=1
            [ "$p1_completed" = "true" ] && part=2
            ts_write "p${part}_desc"
            ;;
        "$c_obj_ex")
            nex=$(grep -c "<pre><code>" "$object_path")
            [ -z "$exnums" ] && exnums=$(seq "$nex")
            ns=0; for _ in $exnums; do ns=$((ns+1)); done

            i=1
            rm -f "$tmp/view"
            for exnum in $exnums; do
                [ "$ns" -gt 1 ] && echo "$i" >> "$tmp/view"
                [ "$exnum" -gt 0 ] 2> /dev/null ||
                    die "invalid example number -- $exnum" "$c_usage_view"

                [ "$exnum" -gt "$nex" ] &&
                    die "example $exnum not found, only $nex example(s) exist"

                beg=$(grep -n "<pre><code>" "$object_path" \
                    | cut -f1 -d: \
                    | sed -n "${exnum}p")
                end=$(grep -n "</code></pre>" "$object_path" \
                    | cut -f1 -d: \
                    | sed -n "${exnum}p")
                sed -n "${beg},${end}p" "$object_path" \
                    | sed 's/<pre><code>//g;s,</code></pre>,,g' \
                    | sed 's/<em>//g;s,</em>,,g' \
                    | sed 's/&lt;/</g;s/&gt;/>/g' \
                    | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' \
                    >> "$tmp/view"
                i=$((i+1))
                [ "$ns" -gt 1 ] && [ "$i" -le "$ns" ] && echo >> "$tmp/view"
            done
            ;;
        *) cp "$object_path" "$tmp/view";;
    esac

    $viewer "$tmp/view"
}

c_usage_edit=$(cat <<eof
usage: $aoc [-y YEAR] [-d DAY] edit [-e <exec_name>]

Open the solution source file for the selected puzzle, create it if
non-existent.

options:
    -e <exec_name>      set executable name
eof
)

edit_cmd() {
    name="$c_exec_name"
    OPTIND=1
    while getopts n: flag; do
        case "$flag" in
            n) name="$OPTARG";;
            *) die "invalid flag" "$c_usage_edit"
        esac
    done
    shift $((OPTIND-1))

    [ -n "$*" ] && die "trailing arguments -- $*"

    day_dir="$(echo "$(path_solution "")"*)"
    if [ ! -d "$day_dir" ]; then
        day_dir_pre="$(path_solution "$dirname")"
        printf 'Solution directory name: %s' "$day_dir_pre"
        read -r dir_in
        [ -z "$dir_in" ] && die "no name provided."

        day_dir="$day_dir_pre$dir_in"
        mkdir -p "$day_dir"
    fi

    src="$(echo "$day_dir/$name".*)"

    if [ ! -r "$src" ]; then
        printf 'Solution file name: %s.' "$name"
        read -r ext_in
        [ -z "$ext_in" ] && die "no extension provided."
        extension=$ext_in
        src="$day_dir/$name.$extension"
    fi

    $EDITOR "$src"
}

c_usage_run=$(cat <<eof
usage: $aoc [-y YEAR] [-d DAY] run [<option>].. [<exec>]..

Run the solution for the selected puzzle.

options:
    -i <input>          set puzzle input
    -I <input_file>     set puzzle input file
    -e <example>        set puzzle input to example from puzzle description
    -d                  do not capture stdout, do not store answer
    -g                  run program using gdb, implies -d
eof
)

run_cmd() {
    input=""
    input_file=""
    capture_output="true"
    precmd=""
    debug="false"
    OPTIND=1
    while getopts i:I:e:c:dg flag; do
        case "$flag" in
            i) input=$OPTARG;;
            I) input_file=$OPTARG;;
            e) exnum=$OPTARG;;
            c) precmd=$OPTARG;;
            d) capture_output=false;;
            g) debug=true;;
            *) die "invalid flag" "$c_usage_run"
        esac
    done
    shift $((OPTIND-1))

    [ "$debug" = "true" ] && capture_output="false"

    day_dir="$(echo "$(path_solution "")"*)"
    [ -d "$day_dir" ] || die "no solution directory at $day_dir"

    if [ -n "$exnum" ]; then
        view_cmd -ccat ex "$exnum" > "$tmp/example"
        input_file="$tmp/example"
    fi

    provided_input=false
    if [ -n "$input" ]; then
        input_file="$tmp/input"
        echo "$input" > "$input_file"
    elif [ -z "$input_file" ]; then
        input_file=$(path_obj "$c_obj_input")
        [ -r "$input_file" ] || fetch_cmd "input"
        provided_input=true
    fi

    [ -r "$input_file" ] || die "can't read input file"

    [ -z "$*" ] && set -- solution
    for exec_name in "$@"; do
        exe="$day_dir/$exec_name"
        make -s "$exe" || die "build failed"
        [ -x "$exe" ] || die "build failed -- no executable file"

        cmd="'./$exe' < '$input_file'"
        [ -n "$precmd" ] && cmd="$precmd $cmd"
        [ "$debug" = "true" ] && cmd="gdb -ex 'set args < $input_file' '$exe'"
        [ "$capture_output" = "true" ] && cmd="$cmd > '$tmp/answer'"
        eval "$cmd" || die "execution failed, use -d for partial output"

        if [ "$capture_output" = "true" ]; then
            [ "$provided_input" = "true" ] && [ -r "$tmp/answer" ] &&
                cp "$tmp/answer" "$(path_obj "$c_obj_ans")"
            cat "$tmp/answer"
        fi
    done
}

c_usage_submit="usage: $aoc [-y YEAR] [-d DAY] submit [<answer>]

Submit an answer for the next uncompleted part of the selected puzzle.
"

submit_cmd() {
    [ -f "$cache/jar" ] || die "not signed in"

    case $(completed_part) in
        0) part=1;;
        1) part=2;;
        2) die "Both parts already completed for day $day $year";;
        *) die "corrupted cache";;
    esac

    ans="$1"
    if [ -z "$ans" ]; then
        if [ -r "$(path_obj "$c_obj_ans")" ]; then
            ans=$(tail -n +"$part" "$(path_obj "$c_obj_ans")" | head -n1)
        else
            die "answer not provided and no answer file found" "$c_usage_submit"
        fi
    fi

    [ -z "$ans" ] && die "no answer available for part $part"

    printf "Submit answer \"%s\" for part %d of day %d, %d (y/N)? " \
           "$ans" "$part" "$day" "$year"
    read -r prompt
    echo

    if [ "$prompt" != "${prompt#[Yy]}" ]; then
        request "$c_url_base/$year/day/$day/answer" \
            --data "level=$part&answer=$ans" > "$tmp/submit"

        if grep -q "That's the right answer!" "$tmp/submit"; then
            # Update completion in cache
            if [ -r "$cache/completed_$year" ]; then
                sed -i ''"$day"' s/.*/'$part'/' "$cache/completed_$year"
            fi

            ts_write "p${part}_success"

            ts_ul=$(ts_diff unlock p${part}_success)
            [ -n "$ts_ul" ] && echo "Time since puzzle unlocked:            $ts_ul"

            ts_p1=$(ts_diff p1_desc p${part}_success)
            [ -n "$ts_p1" ] && echo "Time since reading part 1 description: $ts_p1"

            ts_p2=$(ts_diff p2_desc p${part}_success)
            [ -n "$ts_p2" ] && echo "Time since reading part 2 description: $ts_p2"

            ts_fa=$(ts_diff p${part}_fail p${part}_success)
            [ -n "$ts_fa" ] && echo "Time since first submission attempt:   $ts_fa"

            # create git commit
            {
                git add "$(path_solution "")"*/solution.* &&
                    git commit -qm "$year day $day part $part"
            } 2>/dev/null

            printf "\nThat's the right answer!\n"
        else
            ts_write "p${part}_fail"

            grep '<article>' "$tmp/submit" \
                | sed 's/<[^>]*>/ /g' \
                | tr -s '[:space:]' \
                | sed 's/^\s*//g;s/[!.][^!^.]*$/!/'
        fi
    else
        echo "Submission cancelled."
    fi
}

c_usage_clean="usage: $aoc clean

Remove all build files and cached items.
"

clean_cmd() {
    [ -n "$*" ] && die "trailing args -- $*"
    make -s clean
    rm -rf "$cache"
    find . -type f -name "${c_exec_name:?}" -print0 | xargs -0 rm
}

c_usage_help="usage: $aoc help <command>

Show info about commands.

$c_commands"

help_cmd() {
    if [ -z "$*" ]; then
        echo "$aoc -- Advent of Code helper script"
        printf '\n%s\n' "$c_usage"
    fi
    for topic in "$@"; do
        case "$topic" in
            init) echo "$c_usage_init";;
            select) echo "$c_usage_select";;
            auth) echo "$c_usage_auth";;
            status) echo "$c_usage_status";;
            fetch) echo "$c_usage_fetch";;
            view) echo "$c_usage_view";;
            edit) echo "$c_usage_edit";;
            run) echo "$c_usage_run";;
            submit) echo "$c_usage_submit";;
            clean) echo "$c_usage_clean";;
            help) echo "$c_usage_help";;
            *) die "invalid topic -- $topic" "$c_usage_help";
        esac
        echo
    done
}

year=;day=
while getopts y:d: flag; do
    case "$flag" in
        y) year="$OPTARG";;
        d) day="$OPTARG";;
        *) die "invalid flag" "$c_usage"
    esac
done
shift $((OPTIND-1))

cmd=$1
[ -z "$cmd" ] && die "no command provided" "$c_usage"
shift 1

cache="${XDG_cache_HOME:-$HOME/.cache}"
cache="./.aoc"

[ "$cmd" = "init" ] && init_cmd "$@"

[ -d "$cache" ] || die "no cache at '$cache', use $aoc init to create."

# Cache default selections if not cached
[ -r "$cache/year" ] || echo "$c_start_year" > "$cache/year"
[ -r "$cache/day"  ] || echo "$c_start_day"  > "$cache/day"

cached_year=$(cat "$cache/year")
cached_day=$(cat "$cache/day")

# Get cached selections if not set
[ -z "$year" ] && year=$cached_year
[ -z "$day"  ] &&  day=$cached_day

# trim leading whitespace
year=${year#"${year%%[![:space:]]*}"}
day=${day#"${day%%[![:space:]]*}"}

# Assert valid selections
[ "$year" -ge "$c_start_year" ] 2> /dev/null \
    || die "invalid year -- $year"
{ [ "$day" -ge "$c_start_day" ] && [ "$day" -le "$c_end_day" ]; } 2> /dev/null \
    || die "invalid day -- $day"

tmp="$(mktemp -d)"

case "$cmd" in
    init) ;;
    select) select_cmd "$@";;
    auth|authenticate) auth_cmd "$@";;
    status) status_cmd "$@";;
    fetch|get) fetch_cmd "$@";;
    edit) edit_cmd "$@";;
    view|show) view_cmd "$@";;
    run|exec) run_cmd "$@";;
    submit) submit_cmd "$@";;
    clean) clean_cmd "$@";;
    help) help_cmd "$@";;
    *) die "invalid command -- $cmd" "$c_usage";;
esac

rm -rf "$tmp"

exit 0
