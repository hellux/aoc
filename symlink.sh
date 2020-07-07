script_repo="$(pwd)"
files="Makefile aoc.sh"

solution_repo="$1"

for f in $files; do
    ln -s "$script_repo/$f" "$solution_repo/$f"
done
