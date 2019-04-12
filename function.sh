function handler () {
  EVENT_DATA=$1
  echo "$EVENT_DATA" 1>&2;
  RESPONSE='Uploaded!'

  echo $RESPONSE
}
