ret=$(get_connect_url_and_security)

connect_url=$(echo "$ret" | cut -d "@" -f 1)
security=$(echo "$ret" | cut -d "@" -f 2)

level="${args[--level]}"
connector="${args[--connector]}"

if [[ ! -n "$connector" ]]
then
    log "✨ --connector flag was not provided, applying command to all connectors"
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

log "🔰 also setting io.confluent.kafka.schemaregistry.client.rest.RestService (to see schema registry rest requests) to $level"
playground debug log-level set -p "io.confluent.kafka.schemaregistry.client.rest.RestService" -l $level
log "🔗 also setting org.apache.kafka.connect.runtime.TransformationChain (to see records before and after SMTs) to $level"
playground debug log-level set -p "org.apache.kafka.connect.runtime.TransformationChain" -l $level

items=($connector)
for connector in ${items[@]}
do
    tmp=$(curl -s $security "$connect_url/connectors/$connector" | jq -r '.config."connector.class"')
    package="${tmp%.*}"
    # log "🧬 Set log level for connector $connector to $level"
    playground debug log-level set -p "$package" -l $level
done