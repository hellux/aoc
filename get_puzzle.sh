# usage: ./get_input.sh [-p] <year> <day>
# flags:
#   -p  do not fetch input, only puzzle

if [ "$1" = "-p" ]; then
    all=false
    shift 1
else
    all=true
fi

JAR="cookies.jar"
[ -f "$JAR" ] || (echo "no session cookie" && exit)

year="$1"
[ -z "$year" ] && exit 1
day="$(printf "%02d" $2)"
[ -z "$day" ] && exit 1

if [ "$all" = "true" ]; then
    day_dir="$(find $year -type d -name 'day'$day'_*' | head -n1)"
    if [ ! -d "$day_dir" ]; then
        printf "puzzle name: "
        read puzzle
        day_dir=$(echo $year/day${day}_$puzzle)
        mkdir $day_dir
    fi

    input="$day_dir/input"

    code=$(curl -b "$JAR" -o $input -w '%{http_code}' \
        "https://adventofcode.com/$year/day/$day/input")
    if [ "$code" -eq 400 ]; then
        rm "$input"
        echo "not logged in"
        exit 1
    fi
fi

curl -b "$JAR" "https://adventofcode.com/$year/day/$day" > "puzzle.html"