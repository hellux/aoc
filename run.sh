# usage: ./run.sh year day
#        ./run.sh -i "INPUT" year day
#        ./run.sh -I INPUT_FILE year day

input=""
input_file=""
while getopts i:I: flag; do
    case "$flag" in
        i) input=$OPTARG;;
        I) input_file=$OPTARG;;
    esac
done
shift $((OPTIND-1))

year=$1
day=$(printf "%02d" $2)
day_dir="$(echo $year/day$day*)"
executable="$day_dir/solution"

if [ -z "$input" ]; then
    [ -z "$input_file" ] && input_file="$day_dir/input"
    input="$(cat "$input_file")"
fi

make $executable && printf "$input" | "./$executable"
