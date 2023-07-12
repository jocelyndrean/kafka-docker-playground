#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

rm -f mongo.pem
rm -f mongo.crt
rm -f mongo.key

log "Create a self-signed certificate"
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=mongodb' -keyout /tmp/mongo.key -out /tmp/mongo.crt -days 365

# https://www.mongodb.com/community/forums/t/mongodb-4-4-2-x509/13868/5
cat mongo.key mongo.crt > mongo.pem

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

log "Creating JKS from pem files"
rm -f truststore.jks
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} keytool -importcert -alias mongoCACert -noprompt -file /tmp/mongo.crt -keystore /tmp/truststore.jks -storepass confluent

if [[ "$OSTYPE" == "darwin"* ]]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

cd -


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.ssl.yml"

# https://www.mongodb.com/docs/manual/tutorial/configure-ssl-clients/
log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
EOF

sleep 2

# https://www.mongodb.com/docs/kafka-connector/current/security-and-authentication/tls-and-x509/
# https://www.mongodb.com/docs/drivers/java/sync/current/fundamentals/connection/tls/
log "Creating MongoDB source connector"
playground connector create-or-update --connector mongodb-source << EOF
{
     "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
     "tasks.max" : "1",
     "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017/?tls=true",
     "database":"inventory",
     "collection":"customers",
     "topic.prefix":"mongo"
}
EOF

# [2023-07-12 17:02:15,124] INFO MongoClient with metadata {"driver": {"name": "mongo-java-driver|sync", "version": "4.7.2"}, "os": {"type": "Linux", "name": "Linux", "architecture": "aarch64", "version": "5.15.49-linuxkit-pr"}, "platform": "Java/Azul Systems, Inc./17.0.7+7-LTS"} created with settings MongoClientSettings{readPreference=primary, writeConcern=WriteConcern{w=null, wTimeout=null ms, journal=null}, retryWrites=true, retryReads=true, readConcern=ReadConcern{level=null}, credential=MongoCredential{mechanism=null, userName='myuser', source='admin', password=<hidden>, mechanismProperties=<hidden>}, streamFactoryFactory=null, commandListeners=[], codecRegistry=ProvidersCodecRegistry{codecProviders=[ValueCodecProvider{}, BsonValueCodecProvider{}, DBRefCodecProvider{}, DBObjectCodecProvider{}, DocumentCodecProvider{}, IterableCodecProvider{}, MapCodecProvider{}, GeoJsonCodecProvider{}, GridFSFileCodecProvider{}, Jsr310CodecProvider{}, JsonObjectCodecProvider{}, BsonCodecProvider{}, EnumCodecProvider{}, com.mongodb.Jep395RecordCodecProvider@62f0ba3a]}, clusterSettings={hosts=[mongodb:27017], srvServiceName=mongodb, mode=SINGLE, requiredClusterType=UNKNOWN, requiredReplicaSetName='null', serverSelector='null', clusterListeners='[com.mongodb.kafka.connect.util.ConnectionValidator$1@c9f2f1f]', serverSelectionTimeout='30000 ms', localThreshold='30000 ms'}, socketSettings=SocketSettings{connectTimeoutMS=10000, readTimeoutMS=0, receiveBufferSize=0, sendBufferSize=0}, heartbeatSocketSettings=SocketSettings{connectTimeoutMS=10000, readTimeoutMS=10000, receiveBufferSize=0, sendBufferSize=0}, connectionPoolSettings=ConnectionPoolSettings{maxSize=100, minSize=0, maxWaitTimeMS=120000, maxConnectionLifeTimeMS=0, maxConnectionIdleTimeMS=0, maintenanceInitialDelayMS=0, maintenanceFrequencyMS=60000, connectionPoolListeners=[], maxConnecting=2}, serverSettings=ServerSettings{heartbeatFrequencyMS=10000, minHeartbeatFrequencyMS=500, serverListeners='[]', serverMonitorListeners='[]'}, sslSettings=SslSettings{enabled=false, invalidHostNameAllowed=false, context=null}, applicationName='null', compressorList=[], uuidRepresentation=UNSPECIFIED, serverApi=null, autoEncryptionSettings=null, contextProvider=null} (org.mongodb.driver.client:71)

sleep 5

log "Insert a record"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

# log "Update a record"
# docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
# use inventory
# db.customers.updateOne(
#      { _id: 1 },
#      {
#            \$set: {
#                 email : "thebob2@example.com"
#                 }
#      }
     
# );
# EOF

log "View record"
docker exec -i mongodb mongosh --tls --tlsCertificateKeyFile /tmp/mongo.pem --tlsCertificateKeyFilePassword --tlsAllowInvalidCertificates confluent << EOF
use inventory
db.customers.find().pretty();
EOF

sleep 5

log "Verifying topic mongo.inventory.customers"
playground topic consume --topic mongo.inventory.customers --min-expected-messages 1 --timeout 60
