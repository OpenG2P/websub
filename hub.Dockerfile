FROM maven:3.9.9-eclipse-temurin-11 AS builder

ARG ballerina_version=2201.0.0
ARG ballerina_download_url=https://dist.ballerina.io/downloads/${ballerina_version}/ballerina-${ballerina_version}-swan-lake-linux-x64.deb

RUN wget -q --show-progress ${ballerina_download_url} -O ballerina-linux-installer-x64.deb && \
    dpkg -i ballerina-linux-installer-x64.deb

COPY kafka-admin-client /kafka-admin-client
RUN cd /kafka-admin-client && \
    mvn install -DskipTests -Dgpg.skip

COPY hub /hub
RUN bal build /hub

FROM eclipse-temurin:11.0.25_9-jre-alpine

RUN apk add bash wget curl gettext

ARG container_user_id=1001
ARG container_group_id=1001
ARG container_user=mosip
ARG container_group=mosip

RUN addgroup ${container_group} -g ${container_group_id} && \
    adduser ${container_user} -G ${container_group} -u ${container_user_id} -s bash -D

WORKDIR /home/${container_user}

ARG SOURCE
ARG COMMIT_HASH
ARG COMMIT_ID
ARG BUILD_TIME
LABEL source=${SOURCE}
LABEL commit_hash=${COMMIT_HASH}
LABEL commit_id=${COMMIT_ID}
LABEL build_time=${BUILD_TIME}

COPY --from=builder --chown=${container_user}:${container_group} /hub/target/bin/*.jar hub.jar

ARG hub_config_url
ENV hub_config_file_url_env=${hub_config_url}

USER ${container_user}
EXPOSE 9191

#TODO Link to be parameterized instead of hardcoding
CMD wget -q --show-progress "${hub_config_file_url_env}" -O Config.toml; \
    java -jar -Xms256m -Xmx2048m ./hub.jar
