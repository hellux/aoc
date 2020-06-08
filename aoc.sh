die() {
    str=$1
    shift
    printf 'error: '"$str"'\n' "$@" 1>&2
    rm -rf "$RNT_DIR"
    exit 1
}

BASE_URL="https://adventofcode.com"
AUTH_REDDIT_URL="$BASE_URL/auth/reddit"
INPUT_URL="$BASE_URL/%d/day/%d/input"
DESC_URL="$BASE_URL/%d/day/%d"
ANSWER_URL="$BASE_URL/%d/day/%d/answer"
EVENTS_URL="$BASE_URL/2015/events"
YEAR_URL="$BASE_URL/%d"

EXEC_NAME=solution
AGENT="user-agent: Mozilla/5.0 (X11; Linux x86_64; rv:68.0) Gecko/20100101 Firefox/68.0"

OBJ_FSTR='%s/%s_%d-%02d'
DAY_FSTR='%d/day%02d_'

HTML_SHOW="elinks -dump -dump-color-mode 1 -no-references -no-numbering"
PUZZLE_DIR='puzzles'
JAR='cookies.jar'

USAGE="usage: aoc <command> [<args>]

commands:
    status  -- show login and completion status
    auth    -- authenticate user and create session cookie
    fetch   -- fetch puzzle description or input
    run     -- compile and execute solution
    submit  -- submit answer for puzzle
    clean   -- delete all build files, fetched items, cookies
    help    -- get help about command"
USAGE_STATUS="usage: aoc status [<year>]"
USAGE_SUBMIT="usage: aoc submit <year> <day> <part> <answer>"
USAGE_FETCH="usage: aoc fetch <object> <year> <day>

objects:
    desc    -- puzzle description
    input   -- puzzle input"
USAGE_RUN="usage: aoc run [<flag>...] <year> <day>

flags:
    -i <input>      -- set puzzle input
    -I <input_file> -- set puzzle input file
    -e <exec_name>  -- set executable name"
USAGE_AUTH="usage: aoc auth"
USAGE_HELP="usage: aoc help <command>"

assert_day() {
    day="$2"
    usage="$1"
    [ -z $day ] && die 'day not provided\n\n%s' "$usage"
    [ "$day" -ge 1 -a "$day" -le 25 ] 2> /dev/null \
        || die 'invalid day -- %s\n%s' $day "$usage"
}

assert_year() {
    year="$2"
    usage="$1"
    [ -z "$year" ] && die 'year not provided\n\n%s' "$usage"
    [ "$year" -ge 2015 ] 2> /dev/null \
        || die 'invalid year -- %s\n%s' $year "$usage"
}

request() {
    url="$1"
    shift 1
    args="$*"

    code=$(curl -s -b "$JAR" -o /tmp/aoc_request -w '%{http_code}' $args "$url")

    if [ "$code" != "200" ]; then
        die "HTTP request to '%s' failed. -- code %s" "$url" "$code"
    fi

    cat /tmp/aoc_request
}

status_cmd() {
    year="$1"

    user=""
    if [ ! -f "$JAR" ]; then
        echo "Logged out"
    else
        request "$EVENTS_URL" > /tmp/aoc_events
        if grep "Log In" /tmp/aoc_events; then
            echo "Logic session expired."
        else
            AWK_PARSE_USER='BEGIN { RS="<"; FS=">" }
            $1 == "div class=\"user\"" { printf "%s\n", $2 }'
            user=$(awk "$AWK_PARSE_USER" /tmp/aoc_events | tr -d " ")
            echo "Logged in as $user."
        fi
    fi
    echo

    if [ -z $year ]; then
        echo Available events:
        grep -oE '\[[0-9]{4}\]' /tmp/aoc_events
    else
        assert_year "$USAGE_STATUS" "$year" 

        url="$(printf "$YEAR_URL" "$year")"
        request "$url" > /tmp/aoc_year

        AWK_PARSE_DAYS='BEGIN { RS="<"; FS="=" }
        $1 == "a aria-label" { printf "%s\n", $2 }'
        SED_REPLACE='s/, /\t/;s/two stars/**/;s/one star/* /'

        echo Puzzles $year:
        awk "$AWK_PARSE_DAYS" /tmp/aoc_year \
            | rev | cut -c6- | rev | tr -d '"' \
            | sed "$SED_REPLACE"
    fi
}

auth_cmd() {
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

    echo "Done."
}

fetch_cmd() {
    object=$1
    [ -z "$object" ] && die 'no command provided\n%s' "$USAGE_FETCH"
    shift 1

    year="$1"
    assert_year "$USAGE_FETCH" "$year" 
    day="$2"
    assert_day "$USAGE_FETCH" "$day" 

    output_path="$(printf "$OBJ_FSTR" "$PUZZLE_DIR" "$object" $year $day)"
    url=""
    needs_auth=false
    case "$object" in
        input) url="$(printf "$INPUT_URL" $year $day)"; needs_auth=true;;
        desc) url="$(printf "$DESC_URL" $year $day)";;
        *) die "invalid object to fetch -- %s" "$object";;
    esac

    [ "$needs_auth" = "true" -a ! -f "$JAR" ] && auth_cmd

    mkdir -p "$PUZZLE_DIR"
    echo "Fetching $object..."
    request "$url" > "$output_path"
}

run_cmd() {
    input=""
    input_file=""
    exec_name="$EXEC_NAME"
    while getopts i:I:e: flag; do
        case "$flag" in
            i) input=$OPTARG;;
            I) input_file=$OPTARG;;
            e) exec_name=$OPTARG;;
        esac
    done
    shift $((OPTIND-1))

    year="$1"
    assert_year "$USAGE_RUN" "$year"
    day="$2"
    assert_day "$USAGE_RUN" "$day"

    day_dir="$(echo $(printf "$DAY_FSTR" $year $day)*)"
    executable="$day_dir/$exec_name"

    [ -d "$day_dir" ] || die "no solution directory at %s" "$day_dir"

    if [ -z "$input" ]; then
        if [ -z "$input_file" ]; then
            input_file=$(printf "$OBJ_FSTR" "$PUZZLE_DIR" "input" $year $day)
            [ -r $input_file ] || fetch_cmd "input" $year $day
        fi
        [ ! -r $input_file ] && echo "can't read input file" && exit 1
        input="$(cat "$input_file")"
    fi

    make -s $executable && printf "%s" "$input" | "./$executable"
}

submit_cmd() {
    [ -f "$JAR" ] || auth_cmd

    year="$1"
    assert_year "$USAGE_SUBMIT" "$year" 
    day="$2"
    assert_day "$USAGE_SUBMIT" "$day" 
    part="$3"
    [ -z "$part" ] && die "part not provided\n%s" "$USAGE_SUBMIT"
    [ "$part" = 1 -o "$part" = 2 ] || \
        die "invalid part -- %s\n%s" $part "$USAGE_SUBMIT"
    ans="$4"
    [ -z "$ans" ] && die "answer not provided\n%s" "$USAGE_SUBMIT"

    url="$(printf "$ANSWER_URL" $year $day)"
    request "$url" --data "level=$part&answer=$ans" | $HTML_SHOW
}

clean_cmd() {
    make -s clean
    rm -rf "$PUZZLE_DIR"
    rm -f "$JAR"
    find -type f -name "$EXEC_NAME" | xargs rm -f
}

help_cmd() {
    topic=$1
    if [ -n "$topic" ]; then
        shift
        case "$topic" in
            auth) echo "$USAGE_AUTH";;
            status) echo "$USAGE_STATUS";;
            fetch) echo "$USAGE_FETCH";;
            run) echo "$USAGE_RUN";;
            submit) echo "$USAGE_SUBMIT";;
            clean) echo "$USAGE_CLEAN";;
            help) echo "$USAGE_HELP";;
            *) die 'invalid topic -- %s' "$topic";
        esac
    else
        echo "aoc -- Advent of Code helper script"
        printf '\n%s\n\n%s\n' "$USAGE_HELP" "$USAGE" 
    fi
    [ -n "$1" ] && warn 'excess arguments -- %s' "$*"
}

command=$1
[ -z "$command" ] && die 'no command provided\n\n%s' "$USAGE"
shift 1

case $command in
    auth) auth_cmd "$@";;
    status) status_cmd "$@";;
    fetch) fetch_cmd "$@";;
    run) run_cmd "$@";;
    submit) submit_cmd "$@";;
    clean) clean_cmd "$@";;
    help) help_cmd "$@";;
    *) die 'invalid command -- %s\n\n%s' "$command" "$USAGE";;
esac

rm -f /tmp/aoc_*

exit 0
