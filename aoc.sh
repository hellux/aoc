#!/bin/sh

die() {
    str=$1
    shift
    printf 'error: '"$str"'\n' "$@" 1>&2
    rm -rf "$RUNTIME"
    exit 1
}

APPLICATION=aoc
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE="$CACHE/$APPLICATION"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
RUNTIME="$RUNTIME/$APPLICATION"

JAR="$CACHE/cookies.jar"

START_YEAR=2015
START_DAY=1
END_DAY=25

BASE_URL="https://adventofcode.com"
AUTH_REDDIT_URL="$BASE_URL/auth/reddit"
INPUT_URL="$BASE_URL/%d/day/%d/input"
DESC_URL="$BASE_URL/%d/day/%d"
ANSWER_URL="$BASE_URL/%d/day/%d/answer"
EVENTS_URL="$BASE_URL/$START_YEAR/events"
YEAR_URL="$BASE_URL/%d"

EXEC_NAME=solution
AGENT="user-agent: Mozilla/5.0 (X11; Linux x86_64; rv:68.0) Gecko/20100101 Firefox/68.0"
HTML_DUMP="elinks -no-numbering -no-references -dump -dump-color-mode 1"

OBJ_FSTR="$CACHE/puzzles/aoc_%d-%02d_%s"
DAY_FSTR="%d/day%02d_"

OBJ_ANS=answer
OBJ_INPUT=input
OBJ_DESC=desc

AWK_PARSE_USER='BEGIN { RS="<"; FS=">" }
$1 == "div class=\"user\"" { printf "%s\n", $2 }'
AWK_PARSE_DAYS='BEGIN { RS="<"; FS="=" }
$1 == "a aria-label" { printf "%s\n", $2 }'

COMMANDS="commands:
    select  -- save current selection of year and day
    status  -- show selection, login and completion status
    auth    -- authenticate user and create session cookie
    fetch   -- fetch puzzle description or input
    view    -- view fetched object
    edit    -- edit source file of puzzle solution
    run     -- compile and execute solution
    submit  -- submit answer for puzzle
    clean   -- delete all build files, fetched items, cookies
    help    -- get help about command"
USAGE="usage: aoc.sh [<arg>..] <command> [<arg>..]

flags:
    -y      -- select year
    -d      -- select day
    -q      -- query selection

$COMMANDS"
USAGE_HELP="usage: aoc.sh help <command>

$COMMANDS"

USAGE_AUTH="usage: aoc.sh auth <service>

services:
    reddit"

USAGE_SELECT="usage: aoc.sh [<arg>..] select [<year>|<day>|<command>..]

commands:
    [n]ext  -- select next puzzle
    [p]rev  -- select previous puzzle"

USAGE_STATUS="usage: aoc.sh status [-s] <command>

flags:
    -s      -- synchronize, update cache

commands:
    events  -- events with current completion
    days    -- days with current completion
    login   -- current login status"

OBJECTS="objects:
    desc    -- puzzle description
    input   -- puzzle input"
USAGE_FETCH="usage: aoc.sh fetch <object>

$OBJECTS"
USAGE_VIEW="usage: aoc.sh view [-c <cmd>] <object>

flags:
    -c      -- provide command to view object with

$OBJECTS"

USAGE_EDIT="usage: aoc.sh edit [-e <exec_name>]

flags:
    -e <exec_name>  -- set executable name"
USAGE_RUN="usage: aoc.sh run [<flag>...]

flags:
    -i <input>      -- set puzzle input
    -I <input_file> -- set puzzle input file
    -e <exec_name>  -- set executable name"
USAGE_SUBMIT="usage: aoc.sh submit [<answer>]"

USAGE_CLEAN="usage: aoc.sh clean"

request() {
    url="$1"
    shift 1
    args="$*"

    code=$(curl -s -b "$JAR" -o "$RUNTIME/request" -w '%{http_code}' \
           $args "$url")

    if [ "$code" != "200" ]; then
        die "HTTP request to '%s' failed. -- code %s" "$url" "$code"
    fi

    cat "$RUNTIME/request"
}

completed_part() {
    if [ -r "$CACHE/user" ]; then
        [ -r "$CACHE/completed_$year" ] || status_cmd -s days
        sed -n "${day}p" "$CACHE/completed_$year"
    else
        echo 0
    fi
}

select_cmd() {
    for input in "$@"; do
        case "$input" in
            t|today)
                year=$(date +"%Y")
                day=$(date +"%d");;
            n|next)
                if [ "$day" -eq "$END_DAY" ];
                then year=$((year+1)); day="$START_DAY"
                else day=$((day+1));
                fi;;
            p|prev)
                if [ "$day" -eq "$START_DAY" ];
                then year=$((year-1)); day="$END_DAY"
                else day=$((day-1));
                fi;;
            *)
                if [ 1 -le "$input" ] && \
                   [ "$input" -le "$END_DAY" ]  2> /dev/null;
                then day="$input"
                elif [ "$START_YEAR" -le "$input" ] 2> /dev/null;
                then year="$input"
                else die 'invalid input -- "%s"\n\n%s'
                         "$input" "$USAGE_SELECT"
                fi;;
        esac
    done

    # Update selections cache
    echo "$year" > "$CACHE/year"
    echo "$day"  > "$CACHE/day"

    printf "[ %d - day %02d ] set as current selection.\n" "$year" "$day"
}

status_cmd() {
    sync=false
    OPTIND=1
    while getopts s flag; do
        case "$flag" in
            s) sync=true;;
            *) die 'invalid flag\n\n%s' "$USAGE_STATUS"
        esac
    done
    shift $((OPTIND-1))

    cmd=$1
    if [ -z "$cmd" ]
    then cmd=days
    else shift 1
    fi

    case "$cmd" in
        events)
            [ -r "$CACHE/user" ] || die "not signed in"

            if [ "$sync" = true ] || [ ! -r "$CACHE/events" ]; then
                # Get available events
                request "$EVENTS_URL" > "$RUNTIME/events"
                grep -oE '\[[0-9]{4}\]' "$RUNTIME/events" \
                    | sed 's/\[//;s/\]//' \
                    | sed '1!G;h;$!d' \
                    > "$CACHE/events"

                # Get number of completed stars for each event
                if [ -r "$JAR" ]; then
                    tmp_year=$year
                    while read -r year; do
                        status_cmd -s days > /dev/null
                    done < "$CACHE/events"
                    year=$tmp_year
                fi
            fi

            user=$(cat "$CACHE/user")

            echo "Event completion for [$user]:"
            echo '-----------------------------'
            printf "Year\tGolden\tSilver\tTotal\n"
            while read -r y; do
                f="$CACHE/completed_$y"
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
            done < "$CACHE/events"
            ;;
        days)
            [ -r "$CACHE/user" ] || die "not signed in"

            user=$(cat "$CACHE/user")
            url="$(printf "$YEAR_URL" "$year")"

            if [ "$sync" = true ] || [ ! -r "$CACHE/completed_$year" ]; then
                request "$url" > "$RUNTIME/year"

                for _ in $(seq "$END_DAY"); do echo 0; done > "$RUNTIME/zeroes"
                awk "$AWK_PARSE_DAYS" "$RUNTIME/year" \
                    | rev | cut -c6- | rev | tr -d '"' \
                    | sort -k1 \
                    | sed 's/.*two stars.*/2/;s/.*one star.*/1/;s/Day.*/0/' \
                    | paste "$RUNTIME/zeroes" - | tr -d '\t' \
                    | sed 's/02/2/;s/01/1/' \
                    > "$CACHE/completed_$year"
            fi

            d=1
            echo "$year completion for [$user]:"
            echo '-------------------------------------'
            printf "Day\tStars\tTitle (solution name)\n"
            while read -r comp; do
                desc_path="$(printf "$OBJ_FSTR" "$year" "$d" "$OBJ_DESC")"
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

                day_dir="$(echo "$(printf "$DAY_FSTR" "$year" "$d")"*)"
                if [ -r "$day_dir" ];
                then dirname="($(basename "$day_dir" | cut -c 7-))"
                else dirname=""
                fi

                title="$puzzle_title$dirname"

                if [ "$comp" -eq 1 ]; then stars="*"
                elif [ "$comp" -eq 2 ]; then stars="**"
                else stars=""
                fi

                if [ "$d" -eq "$cached_day" ] && \
                   [ "$year" -eq "$cached_year" ];
                then day_str="[$d]"
                else day_str=" $d"
                fi

                printf '%s\t%s\t%s\n' "$day_str" "$stars" "$title"

                d=$((d+1))
            done < "$CACHE/completed_$year"
            ;;
        login)
            if [ -r "$JAR" ]; then
                if [ "$sync" = true ]; then
                    request "$EVENTS_URL" > "$RUNTIME/events"
                    if grep "Log In" "$RUNTIME/events"; then
                        echo "Logic session expired."
                    else
                        awk "$AWK_PARSE_USER" "$RUNTIME/events" \
                            | tr -d " " > "$CACHE/user"
                    fi
                fi

                echo "Logged in as $(cat "$CACHE/user")."
            else
                echo "Logged out."
            fi
            ;;
        *) die 'invalid command -- "%s"\n\n%s' "$cmd" "$USAGE_STATUS";;
    esac
}

auth_cmd() {
    service="$1"

    [ -z "$service" ] && die "no service provided.\n\n%s" "$USAGE_AUTH"

    case "$service" in
        reddit) auth_reddit;;
        *) die 'invalid service, not implemented -- "%s".\n\n%s' \
               "$service" "$USAGE_AUTH";;
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

    rm -f "$JAR"

    echo "Fetching CSRF token, reddit login session cookie..."
    csrf=$(request "https://www.reddit.com/login/" -c "$JAR" | \
           grep 'csrf_token' | \
           grep -Eo "[0-9a-z]{40}")

    echo "Signing in to reddit..."
    LOGIN_PARAMS="username=$username&password=$password&csrf_token=$csrf"
    code=$(curl -s -H "$AGENT" --data "$LOGIN_PARAMS" \
                -b "$JAR" -c "$JAR" \
                -o /dev/null -w '%{http_code}' \
                "https://www.reddit.com/login" \
           || exit 1)
    if [ "$code" -eq 400 ]; then
        echo "invalid password"
        rm -f "$JAR"
        exit 1
    fi

    echo "Fetching uh token..."
    uh=$(curl -s -H "$AGENT" \
              -b "$JAR" \
              -L "$AUTH_REDDIT_URL" | \
         grep -Eo "[0-9a-z]{50}" | \
         head -n1 \
         || exit 1)

    echo "Authorizing application..."
    AUTH_PARAMS="client_id=macQY9D1vLELaw&duration=temporary&redirect_uri=https://adventofcode.com/auth/reddit/callback&response_type=code&scope=identity&state=x&uh=$uh&authorize=Accept"
    curl -s --data "$AUTH_PARAMS" \
         -H "$AGENT" \
         -b "$JAR" -c "$JAR" \
         -L "https://www.reddit.com/api/v1/authorize" > /dev/null

    # Keep only the needed session cookie.
    sed -i -n '/adventofcode.com/p' "$JAR"

    status_cmd -s login
}

fetch_cmd() {
    object=$1
    [ -z "$object" ] && die 'no object provided\n%s' "$USAGE_FETCH"

    url=""
    needs_auth=false
    case "$object" in
        "$OBJ_INPUT")
            url="$(printf "$INPUT_URL" "$year" "$day")";
            needs_auth=true;;
        "$OBJ_DESC")
            url="$(printf "$DESC_URL" "$year" "$day")";;
        *)
            die 'invalid object to fetch -- "%s"' "$object";;
    esac

    [ "$needs_auth" = "true" -a ! -f "$JAR" ] && die "not signed in"

    output_path="$(printf "$OBJ_FSTR" "$year" "$day" "$object")"
    mkdir -p "$CACHE/puzzles"
    echo "Fetching $object for day $day, $year..."
    request "$url" > "$output_path"
}

view_cmd() {
    viewer="less -r"
    OPTIND=1
    while getopts c: flag; do
        case "$flag" in
            c) viewer="$OPTARG";;
            *) die 'invalid flag\n\n%s' "$USAGE_VIEW"
        esac
    done
    shift $((OPTIND-1))

    object=$1
    [ -z "$object" ] && die 'no object provided\n%s' "$USAGE_VIEW"
    shift 1
    [ -n "$*" ] && die 'trailing arguments -- %s' "$@"

    object_path="$(printf "$OBJ_FSTR" "$year" "$day" "$object")"
    fetch=false
    if [ ! -r "$object_path" ]; then
        # Fetch if non-existent
        fetch=true
    elif [ "$object" = "$OBJ_DESC" ]; then
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

    [ "$fetch" = "true" ] && fetch_cmd "$object"

    case "$object" in
        "$OBJ_DESC")
            beg=$(awk '/<article/ {print FNR; exit}' "$object_path")
            end=$(awk '/<\/article>/ {print FNR}' "$object_path" | tail -n1)
            tail -n +"$beg" "$object_path" | head -n $((end-beg+1)) \
                | $HTML_DUMP > "$RUNTIME/view"
            ;;
        *) cp "$object_path" "$RUNTIME/view";;
    esac

    $viewer "$RUNTIME/view"
}

edit_cmd() {
    extension="*"
    name="$EXEC_NAME"
    OPTIND=1
    while getopts n:e: flag; do
        case "$flag" in
            n) name="$OPTARG";;
            e) extension="$OPTARG";;
            *) die 'invalid flag\n\n%s' "$USAGE_EDIT"
        esac
    done
    shift $((OPTIND-1))

    day_dir="$(echo "$(printf "$DAY_FSTR" "$year" "$day")"*)"
    if [ ! -d "$day_dir" ]; then
        day_dir_pre="$(printf "${DAY_FSTR}%s" "$year" "$day" "$dirname")"
        printf 'Solution directory name: %s' "$day_dir_pre"
        read -r dir_in
        [ -z "$dir_in" ] && die "no name provided."

        day_dir="$day_dir_pre$dir_in"
        mkdir -p "$day_dir"
    fi

    src="$(echo "$day_dir/$name".$extension)"

    if [ ! -r "$src" ]; then
        printf 'Provide file extension: %s.' "$name"
        read -r ext_in
        [ -z "$ext_in" ] && die "no extension provided."
        extension=$ext_in
        src="$day_dir/$name.$extension"
    fi

    $EDITOR "$src"
}

run_cmd() {
    input=""
    input_file=""
    exec_name="$EXEC_NAME"
    OPTIND=1
    while getopts i:I:n: flag; do
        case "$flag" in
            i) input=$OPTARG;;
            I) input_file=$OPTARG;;
            n) exec_name=$OPTARG;;
            *) die 'invalid flag\n\n%s' "$USAGE_RUN"
        esac
    done
    shift $((OPTIND-1))

    day_dir="$(echo "$(printf "$DAY_FSTR" "$year" "$day")"*)"
    exe="$day_dir/$exec_name"

    [ -d "$day_dir" ] || die "no solution directory at %s" "$day_dir"

    if [ -n "$input" ]; then
        input_file="$RUNTIME/input"
        echo "$input" > "$input_file"
    elif [ -z "$input_file" ]; then
        input_file=$(printf "$OBJ_FSTR" "$year" "$day" $OBJ_INPUT)
        [ -r "$input_file" ] || fetch_cmd "input" "$year" "$day"
    fi

    [ -r "$input_file" ] || die "can't read input file"

    answer_file=$(printf "$OBJ_FSTR" $year $day "$OBJ_ANS")
    make -s "$exe" && "./$exe" < "$input_file" > "$answer_file" \
        || die "execution failed"

    cat "$answer_file"
}

submit_cmd() {
    [ -f "$JAR" ] || die "not signed in"

    case $(completed_part) in
        0) part=1;;
        1) part=2;;
        2) die "Both parts already completed for day $day $year";;
        *) die "corrupted cache";;
    esac

    ans="$1"
    if [ -z "$ans" ]; then
        answer_file=$(printf "$OBJ_FSTR" "$year" "$day" "$OBJ_ANS")
        if [ -r "$answer_file" ]; then
            ans=$(tail -n +"$part" "$answer_file" | head -n1)
        else
            die "answer not provided and no answer file found\n%s" \
                "$USAGE_SUBMIT"
        fi
    fi

    [ -z "$ans" ] && die "no answer available for part %d" "$part"

    printf "Submit answer \"%s\" for part %d of day %d, %d (y/N)? " \
           "$ans" "$part" "$day" "$year"
    read -r prompt
    echo

    if [ "$prompt" != "${prompt#[Yy]}" ]; then
        url="$(printf "$ANSWER_URL" "$year" "$day")"
        request "$url" --data "level=$part&answer=$ans" > "$RUNTIME/submit"

        if grep -q "That's the right answer!" "$RUNTIME/submit"; then
            # Update completion in cache
            if [ -r "$CACHE/completed_$year" ]; then
                sed -i ''"$day"' s/.*/'$part'/' "$CACHE/completed_$year"
            fi
        fi

        grep '<article>' "$RUNTIME/submit" \
            | sed 's/<[^>]*>/ /g' \
            | tr -s '[:space:]' \
            | sed 's/^\s*//g;s/[!.][^!^.]*$/!/'
    else
        echo "Submission cancelled."
    fi
}

clean_cmd() {
    make -s clean
    rm -rf "$CACHE"
    find . -type f -name "${EXEC_NAME:?}" -print0 | xargs -0 rm
}

help_cmd() {
    topic=$1
    if [ -n "$topic" ]; then
        shift
        case "$topic" in
            select) echo "$USAGE_SELECT";;
            auth) echo "$USAGE_AUTH";;
            status) echo "$USAGE_STATUS";;
            fetch) echo "$USAGE_FETCH";;
            view) echo "$USAGE_VIEW";;
            edit) echo "$USAGE_EDIT";;
            run) echo "$USAGE_RUN";;
            submit) echo "$USAGE_SUBMIT";;
            clean) echo "$USAGE_CLEAN";;
            help) echo "$USAGE_HELP";;
            *) die 'invalid topic -- "%s"\n\n%s' "$topic" "$USAGE_HELP";
        esac
    else
        echo "aoc.sh -- Advent of Code helper script"
        printf '\n%s\n' "$USAGE"
    fi
    [ -n "$1" ] && warn 'excess arguments -- %s' "$*"
}

[ -d "$RUNTIME" ] || mkdir -p "$RUNTIME"
[ -d "$CACHE" ] || mkdir -p "$CACHE"

# Cache default selections if not cached
[ -r "$CACHE/year" ] || echo "$START_YEAR" > "$CACHE/year"
[ -r "$CACHE/day"  ] || echo "$START_DAY"  > "$CACHE/day"

cached_year=$(cat "$CACHE/year")
cached_day=$(cat "$CACHE/day")

query=false
year=;day=
while getopts qy:d:p: flag; do
    case "$flag" in
        q) query=true;;
        y) year="$OPTARG";;
        d) day="$OPTARG";;
        *) die 'invalid flag\n\n%s' "$USAGE"
    esac
done
shift $((OPTIND-1))

if [ "$query" = "true" ]; then
    if [ -z "$year" ]; then
        printf "Year [%d]: " "$cached_year"
        read -r new
        [ -n "$new" ] && year="$new"
    fi

    if [ -z "$day" ]; then
        printf "Day [%02d]: " "$cached_day"
        read -r new
        [ -n "$new" ] && day="$new"
    fi
fi

# Get cached selections if not set
[ -z "$year" ] && year=$cached_year
[ -z "$day"  ] &&  day=$cached_day

# Assert valid selections
[ "$year" -ge "$START_YEAR" ] 2> /dev/null \
    || die 'invalid year -- "%s"\n' "$year"
[ "$day" -ge "$START_DAY" -a "$day" -le "$END_DAY" ] 2> /dev/null \
    || die 'invalid day -- "%s"\n' "$day"

cmd=$1
[ -z "$cmd" ] && die 'no command provided.\n\n%s' "$USAGE"

shift 1

case "$cmd" in
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
    *) die 'invalid command -- "%s"\n\n%s' "$cmd" "$USAGE";;
esac

rm -rf "$RUNTIME"

exit 0
