// Copyright (c) 2021, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/log;
import ballerina/jwt;

import kafkaHub.config;

const string SUFFIX_GENERAL = "_GENERAL";
const string SUFFIX_ALL_INDIVIDUAL = "_ALL_INDIVIDUAL";
const string SUFFIX_INDIVIDUAL = "_INDIVIDUAL";

# Authorize the subscriber.
#
# + headers - `http:Headers` of request
# + topic - Topic of the message
# + return - `error` if there is any authorization error or else `()`
public isolated function authorizeSubscriber(http:Headers headers, string topic) returns error? {
    string token = check getToken(headers);
    log:printDebug("getting token for Subscriber from request", topic = topic);
    jwt:Payload response = check getValidatedTokenPayload(token);
    string[] rolesArr = response.hasKey(config:SECURITY_JWT_ROLES_FIELD) && response[config:SECURITY_JWT_ROLES_FIELD] is string[] ? <string[]> response[config:SECURITY_JWT_ROLES_FIELD] : [];
    string userId = <string> response[config:SECURITY_JWT_USERID_FIELD];
    log:printDebug("received response for subscriber from auth service", userId = userId, roles = rolesArr, topic = topic);
    if (userId.startsWith(config:PARTNER_USER_ID_PREFIX)) {
        userId = userId.substring(config:PARTNER_USER_ID_PREFIX.length(), userId.length());
    }
    string? partnerID = buildPartnerId(topic);
    string rolePrefix = buildRolePrefix(topic, "SUBSCRIBE_");
    boolean authorized = isSubscriberAuthorized(partnerID, rolePrefix, rolesArr, userId);
    if (!authorized) {
        return error("Subscriber is not authorized");
    }
}

# Authorize the publisher.
#
# + headers - `http:Headers` of request
# + topic - Topic of the message
# + return - `error` if there is any authorization error or else `()`
public isolated function authorizePublisher(http:Headers headers, string topic) returns error? {
    string token = check getToken(headers);
    log:printDebug("got token for publisher from request", topic = topic);
    jwt:Payload response = check getValidatedTokenPayload(token);
    string[] rolesArr = response.hasKey(config:SECURITY_JWT_ROLES_FIELD) && response[config:SECURITY_JWT_ROLES_FIELD] is string[] ? <string[]> response[config:SECURITY_JWT_ROLES_FIELD] : [];
    string? userId = response.hasKey(config:SECURITY_JWT_USERID_FIELD) && response[config:SECURITY_JWT_USERID_FIELD] is string ? <string> response[config:SECURITY_JWT_USERID_FIELD] : null;
    log:printDebug("received response for publisher from auth service", userId = userId, roles = rolesArr, topic = topic);
    string? partnerID = buildPartnerId(topic);
    string rolePrefix = buildRolePrefix(topic, "PUBLISH_");
    boolean authorized = isPublisherAuthorized(partnerID, rolePrefix, rolesArr);
    if (!authorized) {
        return error("Publisher is not authorized");
    }
}

// Token is extracted from the Authorization header
isolated function getToken(http:Headers headers) returns string|error {
    string|error authHeader = check headers.getHeader("Authorization");
    if !(authHeader is error) {
        if authHeader.startsWith("Bearer") {
            return authHeader.trim();
        }
    }
    return error("Authorization token cannot be found");
}

isolated function buildRolePrefix(string topic, string prefix) returns string {
    int? index = topic.indexOf("/");
    if index is int {
        return prefix + topic.substring(index + 1, topic.length());
    } else {
        return prefix + topic;
    }
}

isolated function buildPartnerId(string topic) returns string? {
    int? index = topic.indexOf("/");
    if index is int {
        return topic.substring(0, index);
    }
    return null;
}

isolated function getValidatedTokenPayload(string token) returns jwt:Payload|jwt:Error {
    jwt:ValidatorConfig validatorConfig = {
        issuer: config:SECURITY_JWT_ISSUER,
        signatureConfig: {
            jwksConfig: {
                url: config:SECURITY_JWT_ISSUER_JWKS_URL,
                cacheConfig: {
                    defaultMaxAge: config:SECURITY_JWT_ISSUER_JWKS_MAX_AGE
                }
            }
        }
    };
    return jwt:validate(token, validatorConfig);
}

isolated function isPublisherAuthorized(string? partnerID, string rolePrefix, string[] rolesArr) returns boolean {
    if partnerID is string {
        foreach string role in rolesArr {
            if role == rolePrefix.concat(SUFFIX_ALL_INDIVIDUAL) {
                return true;
            }
        }
    } else {
        foreach string role in rolesArr {
            if role == rolePrefix.concat(SUFFIX_GENERAL) {
                return true;
            }
        }
    }
    return false;
}

isolated function isSubscriberAuthorized(string? partnerID, string rolePrefix, string[] rolesArr, string userId)
                                        returns boolean {
    if partnerID is string {
        foreach string role in rolesArr {
            if role == rolePrefix.concat(SUFFIX_INDIVIDUAL) && partnerID == userId {
                return true;
            }
        }
    } else {
        foreach string role in rolesArr {
            if role == rolePrefix.concat(SUFFIX_GENERAL) {
                return true;
            }
        }
    }
    return false;
}
