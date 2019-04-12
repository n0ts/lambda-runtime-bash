function handler () {
  EVENT_DATA=$1
  echo "$EVENT_DATA" 1>&2;
  RESPONSE=$(cat <<EOS
Echoing request: '$EVENT_DATA'
uname -a: $(uname -a)
awscli version: $(aws --version 2>&1)
jq version: $(jq --version)
EOS
)

  echo $RESPONSE
}
