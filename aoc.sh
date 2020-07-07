#!/bin/sh

die() {
    str=$1
    shift
    printf 'error: '"$str"'\n' "$@" 1>&2
    rm -rf "$RUNTIME"
    exit 1
}

if [ -z "$XDG_CACHE_HOME" ];
then CACHE="$HOME/.cache/aoc"
else CACHE="$XDG_CACHE_HOME/aoc"
fi

if [ -z "$XDG_RUNTIME_DIR" ];
then RUNTIME="/tmp/aoc"
else RUNTIME="$XDG_RUNTIME_DIR/aoc"
fi

PUZZLE_DIR="$CACHE/puzzles"
JAR="$CACHE/cookies.jar"

START_YEAR=2015
START_DAY=1
START_PART=1

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

OBJ_FSTR="$PUZZLE_DIR/aoc_%d-%02d_%s"
DAY_FSTR="%d/day%02d_"

OBJ_ANS=answer
OBJ_INPUT=input
OBJ_DESC=desc

AWK_PARSE_USER='BEGIN { RS="<"; FS=">" }
$1 == "div class=\"user\"" { printf "%s\n", $2 }'
AWK_PARSE_DAYS='BEGIN { RS="<"; FS="=" }
$1 == "a aria-label" { printf "%s\n", $2 }'

COMMANDS="commands:
    select  -- save current selection of year, day and part
    status  -- show selection, login and completion status
    auth    -- authenticate user and create session cookie
    fetch   -- fetch puzzle description or input
    view    -- view fetched object
    edit    -- edit source file of puzzle solution
    run     -- compile and execute solution
    submit  -- submit answer for puzzle
    clean   -- delete all build files, fetched items, cookies
    help    -- get help about command"
USAGE="usage: aoc.sh [<args>] <command> [<args>]

flags:
    -y      -- select year
    -d      -- select day
    -p      -- select part
    -q      -- query selection

$COMMANDS"
USAGE_HELP="usage: aoc.sh help <command>

$COMMANDS"

USAGE_AUTH="usage: aoc.sh auth <service>

services:
    reddit"

USAGE_SELECT="usage: aoc.sh [-y <year>] [-d <day>] [-p <part>] select [command]

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
USAGE_VIEW="usage: aoc.sh view <object>

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

select_cmd() {
    cmd="$1"
    if [ -n "$cmd" ]; then
        case "$cmd" in
            n|next)
                if [ "$day" -eq 25 ];
                then year=$((year+1)); day=1
                else day=$((day+1));
                fi

                part=1;;
            p|prev)
                if [ "$day" -eq 1 ];
                then year=$((year-1)); day=25
                else day=$((day-1));
                fi

                part=1;;
            *) die 'invalid command -- %s\n\n%s' "$cmd" "$USAGE_SELECT"
        esac
    fi

    # Update selections cache
    echo "$year" > "$CACHE/year"
    echo "$day"  > "$CACHE/day"
    echo "$part" > "$CACHE/part"

    printf "[ %d - %02d - part %d ] set as current selection.\n" $year $day $part
}

status_cmd() {
    sync=false
    while getopts s flag; do
        case "$flag" in
            s) sync=true;;
            *) die 'invalid flag\n\n%s' "$USAGE_STATUS"
        esac
    done
    shift $((OPTIND-1))

    cmd=$1
    if [ -z "$cmd" ]
    then cmd=events
    else shift 1
    fi

    case "$cmd" in
        events)
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
                    for y in $(cat "$CACHE/events"); do
                        year=$y
                        status_cmd -s days > /dev/null
                    done
                    year=$tmp_year
                fi
            fi

            printf "Year\tGolden\tSilver\tTotal\n"
            for y in $(cat "$CACHE/events"); do
                f="$CACHE/completed_$y"
                printf "%d" "$y"
                if [ -r "$f" ] && [ -f "$CACHE/user" ]; then
                    golden=$(grep "2$" "$f" | wc -l)
                    silver=$(grep  "1$" "$f" | wc -l)
                    total=$((golden*2 + silver))
                    printf "\t%d\t%d\t%d" $golden $silver $total
                else
                    printf "\t-\t-\t-"
                fi
                echo
            done
            ;;
        days)
            url="$(printf "$YEAR_URL" "$year")"

            if [ "$sync" = true ] || [ ! -r "$CACHE/completed_$year" ]; then
                request "$url" > "$RUNTIME/year"

                echo Puzzles $year:
                awk "$AWK_PARSE_DAYS" "$RUNTIME/year" \
                    | rev | cut -c6- | rev | tr -d '"' \
                    | sed '/[0-9]$/ s/$/\t0/' \
                    | sed 's/, /\t/;s/two stars/2/;s/one star/1/' \
                    | sed 's/Day //' \
                    | sed '1!G;h;$!d' \
                    > "$CACHE/completed_$year"
            fi

            printf "Day\tStars\tTitle (solution name)\n"
            while read -r d comp; do
                object_path="$(printf "$OBJ_FSTR" "$year" "$d" "$OBJ_DESC")"
                if [ -r "$object_path" ]; then
                    title=$(grep '<article' "$object_path" \
                            | awk 'BEGIN {FS="---"; RS=":"} NR==2 {print $1}' \
                            | xargs \
                            | sed "s/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/\</g;
                                   s/&gt;/\>/g; s/&quot;/\"/g; s/&ldquo;/\"/g;
                                   s/&rdquo;/\"/g; s/&apos;/'/g;")

                    src_dir="$(echo $(printf "$DAY_FSTR" $year $d)*)"
                    if [ -r "$src_dir" ]; then
                        name=$(basename $src_dir | cut -c 7-)
                        title="$title ($name)"
                    fi
                else
                    title=""
                fi

                if [ "$comp" -eq 1 ]; then
                    stars="*"
                elif [ $comp -eq 2 ]; then
                    stars="**"
                else
                    stars=""
                fi

                printf '%d\t%s\t%s\n' "$d" "$stars" "$title"
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
        *) die 'invalid service, not implemented -- %s.\n\n%s' \
               "$service" "$USAGE_AUTH";;
    esac
}

auth_reddit() {
    # Get credentials from user.
    printf "reddit username: "
    read username
    stty -echo
    printf "password: "
    read password
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
        "$OBJ_INPUT") url="$(printf "$INPUT_URL" $year $day)"; needs_auth=true;;
        "$OBJ_DESC") url="$(printf "$DESC_URL" $year $day)";;
        *) die 'invalid object to fetch -- "%s"' "$object";;
    esac

    [ "$needs_auth" = "true" -a ! -f "$JAR" ] && auth_cmd

    output_path="$(printf "$OBJ_FSTR" $year $day "$object")"
    mkdir -p "$PUZZLE_DIR"
    echo "Fetching $object for day $day, $year..."
    request "$url" > "$output_path"
}

view_cmd() {
    object=$1
    [ -z "$object" ] && die 'no object provided\n%s' "$USAGE_VIEW"

    object_path="$(printf "$OBJ_FSTR" "$year" "$day" "$object")"
    fetch=false
    if [ -r "$object_path" ]; then
        # Fetch if second part available
        p1_completed=false
        p2_downloaded=false
        comp="$CACHE/completed_$year"

        [ -r "$comp" ] && head -n 12 $comp | tail -n1 | grep -q '2$' \
            && p1_completed=true
        [ $(grep '<article' "$object_path" | wc -l) -eq 2 ] \
            && p2_downloaded=true
        if [ "$1_completed" = true ] && [ "$p2_downloaded" != true ]
        then fetch=true
        fi
    else
        # Fetch if non-existent
        fetch=true
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

    less "$RUNTIME/view"
}

edit_cmd() {
    extension="*"
    name="$EXEC_NAME"
    while getopts e: flag; do
        case "$flag" in
            n) name="$OPTARG";;
            e) extension="$OPTARG";;
            *) die 'invalid flag\n\n%s' "$USAGE_EDIT"
        esac
    done
    shift $((OPTIND-1))

    day_dir="$(echo $(printf "$DAY_FSTR" $year $day)*)"
    [ -d "$day_dir" ] || die '"%s" is not a directory.' "$day_dir"

    src="$(echo $day_dir/$name.$extension)"

    $EDITOR "$src"
}

run_cmd() {
    input=""
    input_file=""
    exec_name="$EXEC_NAME"
    while getopts i:I:n: flag; do
        case "$flag" in
            i) input=$OPTARG;;
            I) input_file=$OPTARG;;
            n) exec_name=$OPTARG;;
            *) die 'invalid flag\n\n%s' "$USAGE_RUN"
        esac
    done
    shift $((OPTIND-1))

    day_dir="$(echo $(printf "$DAY_FSTR" $year $day)*)"
    exe="$day_dir/$exec_name"

    [ -d "$day_dir" ] || die "no solution directory at %s" "$day_dir"

    if [ -z "$input" ]; then
        if [ -z "$input_file" ]; then
            input_file=$(printf "$OBJ_FSTR" $year $day $OBJ_INPUT)
            [ -r $input_file ] || fetch_cmd "input" $year $day
        fi
        [ ! -r $input_file ] && echo "can't read input file" && exit 1
        input="$(cat "$input_file")"
    fi

    answer_file=$(printf "$OBJ_FSTR" $year $day "$OBJ_ANS")
    make -s "$exe" && printf "%s" "$input" | "./$exe" > $answer_file \
        || die "execution failed"

    cat "$answer_file"
}

submit_cmd() {
    [ -f "$JAR" ] || auth_cmd

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

    printf "Submit answer \"%s\" for part %d of day %d, %d (y/N)? " \
           "$ans" "$part" "$day" "$year"
    read prompt
    echo

    if [ "$prompt" != "${prompt#[Yy]}" ]; then
        url="$(printf "$ANSWER_URL" "$year" "$day")"
        request "$url" --data "level=$part&answer=$ans" > "$RUNTIME/submit"

        if grep -q "You have completed" "$RUNTIME/submit"; then
            # Update completion in cache
            if [ -r "$CACHE/completed_$year" ]; then
                sed -i 's/'$day'\t./'$day'\t'$part'/' "$CACHE/completed_$year"
            fi

            if [ "$part" -eq 1 ];
            then part=2;
            else part=1;
            fi
        fi

        grep '<article>' "$RUNTIME/submit" | sed 's/<[^>]*>//g'
    else
        echo "Submission cancelled."
    fi
}

clean_cmd() {
    make -s clean
    rm -rf "$CACHE"
    find . -type f -print0 -name "$EXEC_NAME" | xargs rm -f
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
[ -r "$CACHE/part" ] || echo "$START_PART" > "$CACHE/part"

cached_year=$(cat "$CACHE/year")
cached_day=$(cat "$CACHE/day")
cached_part=$(cat "$CACHE/part")

query=false
year=;day=;part=
while getopts qy:d:p: flag; do
    case "$flag" in
        q) query=true;;
        y) year="$OPTARG";;
        d) day="$OPTARG";;
        p) part="$OPTARG";;
        *) die 'invalid flag\n\n%s' "$USAGE"
    esac
done
shift $((OPTIND-1))

if [ "$query" = "true" ]; then
    if [ -z "$year" ]; then
        printf "Year [$cached_year]: "
        read new
        [ -n "$new" ] && year="$new"
    fi

    if [ -z "$day" ]; then
        printf "Day [$cached_day]: "
        read new
        [ -n "$new" ] && day="$new"
    fi

    if [ -z "$part" ]; then
        printf "Part [$cached_part]: "
        read new
        [ -n "$new" ] && day="$new"
    fi
fi

# Get cached selections if not set
[ -z "$year" ] && year=$cached_year
[ -z "$day"  ] &&  day=$cached_day
[ -z "$part" ] && part=$cached_part

# Assert valid selections
[ "$year" -ge "$START_YEAR" ] 2> /dev/null \
    || die 'invalid year -- "%s"\n' "$year"
[ "$day" -ge 1 -a "$day" -le 25 ] 2> /dev/null \
    || die 'invalid day -- "%s"\n' "$day"
[ "$part" = 1 -o "$part" = 2 ] 2> /dev/null \
    || die 'invalid part -- "%s"\n' "$part"

cmd=$1
[ -z "$cmd" ] && die 'no command provided.\n\n%s' "$USAGE"

shift 1

case "$cmd" in
    select) select_cmd "$@";;
    auth) auth_cmd "$@";;
    status) status_cmd "$@";;
    fetch) fetch_cmd "$@";;
    edit) edit_cmd "$@";;
    view) view_cmd "$@";;
    run) run_cmd "$@";;
    submit) submit_cmd "$@";;
    clean) clean_cmd "$@";;
    help) help_cmd "$@";;
    *) die 'invalid command -- "%s"\n\n%s' "$cmd" "$USAGE";;
esac

rm -rf "$RUNTIME"

exit 0
