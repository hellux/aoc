#!/bin/sh

JAR="cookies.jar"
AGENT="user-agent: Mozilla/5.0 (X11; Linux x86_64; rv:68.0) Gecko/20100101 Firefox/68.0"

# Get credentials from user.
printf "reddit username: "
read username
stty -echo
printf "password: "
read password
stty echo
printf "\n"

# Get csrf token and session cookie for reddit login.
csrf=$(curl -c "$JAR" "https://www.reddit.com/login/" | \
       grep 'csrf_token' | \
       grep -Eo "[0-9a-z]{40}" \
       || exit 1)

# Sign in to reddit.
LOGIN_PARAMS="username=$username&password=$password&csrf_token=$csrf"
code=$(curl -H "$AGENT" --data "$LOGIN_PARAMS" \
            -b "$JAR" -c "$JAR" \
            -o /dev/null -w '%{http_code}' \
            "https://www.reddit.com/login" \
       || exit 1)
[ "$code" -eq 400 ] && echo "invalid password" && exit 

# Get uh token from reddit.
uh=$(curl -H "$AGENT" \
          -b "$JAR" \
          -L "https://adventofcode.com/auth/reddit" | \
     grep -Eo "[0-9a-z]{50}" | \
     head -n1 \
     || exit 1)

# Authorize application and obtain code from reddit.
AUTH_PARAMS="client_id=macQY9D1vLELaw&duration=temporary&redirect_uri=https://adventofcode.com/auth/reddit/callback&response_type=code&scope=identity&state=x&uh=$uh&authorize=Accept"
curl --data "$AUTH_PARAMS" \
     -H "$AGENT" \
     -b "$JAR" -c "$JAR" \
     -L "https://www.reddit.com/api/v1/authorize" > /dev/null

# Keep only the needed session cookie.
sed -i -n '/adventofcode.com/p' "$JAR"
