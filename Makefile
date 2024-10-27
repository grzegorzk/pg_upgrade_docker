#!/usr/bin/env make

#    Copyright 2024 Grzegorz Klimaszewski
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

BASH=/usr/bin/env bash
SHELL=${BASH}
DOCKER=podman

NPROC_ULIMITS=7000

MIN_SUPPORTED_MAKE_VERSION=4
IS_MAKE_VERSION_SUPPORTED=
ifeq (${MIN_SUPPORTED_MAKE_VERSION},$(firstword $(sort $(MAKE_VERSION) ${MIN_SUPPORTED_MAKE_VERSION})))
	IS_MAKE_VERSION_SUPPORTED=yes
endif

POSTGRES_DATA=$${POSTGRES_DATA?Please provide POSTGRES_DATA}
POSTGRES_VERSION=$${POSTGRES_VERSION?Please provide POSTGRES_VERSION}
POSTGRES_IMAGE_NAME=docker.io/library/postgres:${POSTGRES_VERSION}
POSTGRES_CONTAINER_NAME=pg_${POSTGRES_VERSION}
POSTGRES_RUNNING_CONTAINER_ID=$$(${DOCKER} ps -aqf "name=${POSTGRES_CONTAINER_NAME}")

POSTGRES_OLD_VERSION=$${POSTGRES_OLD_VERSION?Please provide POSTGRES_OLD_VERSION}
POSTGRES_OLD_IMAGE_NAME=docker.io/library/postgres:${POSTGRES_OLD_VERSION}

POSTGRES_NEW_VERSION=$${POSTGRES_NEW_VERSION?Please provide POSTGRES_NEW_VERSION}
POSTGRES_NEW_IMAGE_NAME=docker.io/library/postgres:${POSTGRES_NEW_VERSION}
POSTGRES_NEW_IMAGE_CONTAINER_NAME=pg_new
POSTGRES_NEW_IMAGE_RUNNING_CONTAINER_ID=$$(${DOCKER} ps -aqf "name=${POSTGRES_NEW_IMAGE_CONTAINER_NAME}")

PG_UPGRADE_IMAGE_NAME=pg_upgrade_${POSTGRES_OLD_VERSION}_${POSTGRES_NEW_VERSION}
PG_UPGRADE_CONTAINER_NAME=pg_upgrade_${POSTGRES_OLD_VERSION}_${POSTGRES_NEW_VERSION}
PG_UPGRADE_RUNNING_CONTAINER_ID=$$(${DOCKER} ps -aqf "name=${PG_UPGRADE_CONTAINER_NAME}")
POSTGRES_DATA_MIGRATED="${CURDIR}"/db/data_migrated_${POSTGRES_NEW_VERSION}

MAKERC=.makerc
include ${CURDIR}/${MAKERC}


list:
	@ if [ -n ${IS_MAKE_VERSION_SUPPORTED} ]; then \
		$(MAKE) -pRrq -f Makefile : 2>/dev/null \
			| grep -e "^[^[:blank:]]*:$$\|#.*recipe to execute" \
			| grep -B 1 "recipe to execute" \
			| grep -e "^[^#]*:$$" \
			| sed -e "s/\(.*\):/\1/g" \
			| sort; \
	else \
		echo "Sorry, your version of make is too old to run this target, please update to version ${MIN_SUPPORTED_MAKE_VERSION} or higher."; \
	fi

build_pg_upgrade_image:
	@ ${DOCKER} build \
		--net=private \
		--progress=plain \
		--file "${CURDIR}"/Dockerfile \
		--build-arg POSTGRES_OLD_IMAGE_NAME=${POSTGRES_OLD_IMAGE_NAME} \
		--build-arg POSTGRES_NEW_IMAGE_NAME=${POSTGRES_NEW_IMAGE_NAME} \
		--build-arg POSTGRES_OLD_VERSION=${POSTGRES_OLD_VERSION} \
		-t ${PG_UPGRADE_IMAGE_NAME} .

start_postgres:
	@ if [ -n "${POSTGRES_RUNNING_CONTAINER_ID}" ]; then \
		echo "It appears '${POSTGRES_CONTAINER_NAME}' is running, please wait for the process to complete or stop this containers and try again"; \
	elif [ ! -f "${CURDIR}"/secrets/POSTGRES_PASSWORD_FILE ]; then \
		echo "'${CURDIR}/secrets/POSTGRES_PASSWORD_FILE' is missing, please create this file - it should contain password to your current database POSTGRES_PASSWORD"; \
	else \
		[ -d "${POSTGRES_DATA}" ] && FOREIGN_POSTGRES_DATA=1 || mkdir -p "${POSTGRES_DATA}" \
		&& touch "${CURDIR}"/secrets/.env \
		&& echo "Removing container POSTGRES_PASSWORD_FILE secret" \
		&& ${DOCKER} secret rm POSTGRES_PASSWORD_FILE 2>/dev/null || true \
		&& echo "Creating container POSTGRES_PASSWORD_FILE secret" \
		&& ${DOCKER} secret create --driver=file POSTGRES_PASSWORD_FILE "${CURDIR}"/secrets/POSTGRES_PASSWORD_FILE \
		&& ${DOCKER} run \
			-d \
			--restart always \
			--shm-size=256m \
			--ulimit nofile=20000:40000 \
			--ulimit nproc=${NPROC_ULIMITS} \
			-v "${POSTGRES_DATA}":/var/lib/postgresql/data \
			--secret POSTGRES_PASSWORD_FILE,uid=999,gid=999 \
			-e POSTGRES_PASSWORD_FILE=/run/secrets/POSTGRES_PASSWORD_FILE \
			--env-file="${CURDIR}"/secrets/.env \
			--name ${POSTGRES_CONTAINER_NAME} \
			${POSTGRES_IMAGE_NAME} \
				-N 5000 \
		&& echo "Waiting for postgres to start in ${POSTGRES_CONTAINER_NAME}" \
		&& grep -q "database system is ready to accept connections" <(${DOCKER} logs -f ${POSTGRES_CONTAINER_NAME} 2>&1) \
		&& echo "Postgres running in ${POSTGRES_CONTAINER_NAME}" \
		&& echo "Creating marker within ${POSTGRES_CONTAINER_NAME}" \
		&& [ ! -n "$${FOREIGN_POSTGRES_DATA}" ] && ${DOCKER} exec -it ${POSTGRES_CONTAINER_NAME} touch /var/lib/postgresql/data/.MARKER || echo "Started postgres on db created by foreign process" \
		&& echo "${POSTGRES_CONTAINER_NAME} started"; \
	fi

stop_postgres:
	@ if [ ! -n "${POSTGRES_RUNNING_CONTAINER_ID}" ]; then \
		echo "It appears '${POSTGRES_CONTAINER_NAME}' is already stopped"; \
	else \
		echo "Stopping ${POSTGRES_CONTAINER_NAME}" \
		&& sleep 1 \
		&& ${DOCKER} stop ${POSTGRES_CONTAINER_NAME} \
		&& ${DOCKER} rm ${POSTGRES_CONTAINER_NAME}; \
	fi

remove_postgres_data:
	@ if [ -n "${POSTGRES_RUNNING_CONTAINER_ID}" ]; then \
		echo "It appears '${POSTGRES_CONTAINER_NAME}' is running, please wait for the process to complete or stop this containers and try again"; \
	else \
		mkdir -p "${POSTGRES_DATA}" \
		&& ${DOCKER} run \
			-it \
			--rm \
			--shm-size=256m \
			--ulimit nofile=20000:40000 \
			--ulimit nproc=${NPROC_ULIMITS} \
			-v "${POSTGRES_DATA}":/var/lib/postgresql/data \
			--name ${POSTGRES_CONTAINER_NAME} \
			--entrypoint /bin/bash \
			${POSTGRES_IMAGE_NAME} \
				-c ' \
				[ ! -f /var/lib/postgresql/data/.MARKER ] && echo "This database was not created by us, refusing to delete" && exit 1 \
				|| rm -rf /var/lib/postgresql/data/* \
				&& rm -rf /var/lib/postgresql/data/.* \
				&& chown root:root /var/lib/postgresql/data;' \
		&& rm -r "${POSTGRES_DATA}"; \
	fi


pg_upgrade:
	@ if [ ! -d "${POSTGRES_DATA}" ]; then \
		echo "'${POSTGRES_DATA}' does not seem to be valid path, please provide valid path to existing POSTGRES_DATA folder"; \
	elif [ -n "${POSTGRES_NEW_IMAGE_RUNNING_CONTAINER_ID}" ] || [ -n "${PG_UPGRADE_RUNNING_CONTAINER_ID}" ]; then \
		echo "It appears either '${POSTGRES_NEW_IMAGE_RUNNING_CONTAINER_ID}' or '${PG_UPGRADE_CONTAINER_NAME}' is running, please wait for the process to complete or stop those containers and try again"; \
	elif [ -d "${POSTGRES_DATA_MIGRATED}" ]; then \
		echo "'${POSTGRES_DATA_MIGRATED}' already exists - it might be a leftover from previous migration, please remove this directory and try again"; \
	elif [ ! -f "${CURDIR}"/secrets/POSTGRES_PASSWORD_FILE ]; then \
		echo "'${CURDIR}/secrets/POSTGRES_PASSWORD_FILE' is missing, please create this file - it should contain password to your current database POSTGRES_PASSWORD"; \
	else \
		touch "${CURDIR}"/secrets/.env; \
		echo "Removing container POSTGRES_PASSWORD_FILE secret"; \
		${DOCKER} secret rm POSTGRES_PASSWORD_FILE 2>/dev/null || true; \
		echo "Creating container POSTGRES_PASSWORD_FILE secret"; \
		${DOCKER} secret create --driver=file POSTGRES_PASSWORD_FILE "${CURDIR}"/secrets/POSTGRES_PASSWORD_FILE; \
		echo "Start new postgres in '${POSTGRES_NEW_IMAGE_RUNNING_CONTAINER_ID}' and create empty db in '${POSTGRES_DATA_MIGRATED}'"; \
		$(MAKE) -s start_postgres POSTGRES_VERSION=${POSTGRES_NEW_VERSION} POSTGRES_DATA="${POSTGRES_DATA_MIGRATED}" \
		&& $(MAKE) -s stop_postgres POSTGRES_VERSION=${POSTGRES_NEW_VERSION} \
		&& echo "Build ${PG_UPGRADE_IMAGE_NAME}" \
		&& $(MAKE) -s build_pg_upgrade_image \
		&& echo "Run ${PG_UPGRADE_IMAGE_NAME}" \
		&& ${DOCKER} run \
			-it \
			--rm \
			--shm-size=256m \
			--ulimit nofile=20000:40000 \
			--ulimit nproc=${NPROC_ULIMITS} \
			-v "${POSTGRES_DATA}":/var/lib/postgresql/data_old \
			-v "${POSTGRES_DATA_MIGRATED}":/var/lib/postgresql/data_migrated \
			--secret POSTGRES_PASSWORD_FILE,uid=999,gid=999 \
			-e POSTGRES_PASSWORD_FILE=/run/secrets/POSTGRES_PASSWORD_FILE \
			--env-file="${CURDIR}"/secrets/.env \
			--name ${PG_UPGRADE_CONTAINER_NAME} \
			--entrypoint /bin/bash \
			--user postgres \
			${PG_UPGRADE_IMAGE_NAME} \
				-c " \
					cd /var/lib/postgresql && \
					pg_upgrade \
						--old-datadir '/var/lib/postgresql/data_old' \
						--new-datadir '/var/lib/postgresql/data_migrated' \
						--old-bindir '/usr/lib/postgresql/${POSTGRES_OLD_VERSION}/bin' \
						--new-bindir '/usr/lib/postgresql/${POSTGRES_NEW_VERSION}/bin' \
						--username postgres \
				" \
		&& echo "DB migrated, "; \
	fi
