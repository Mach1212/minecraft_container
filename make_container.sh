#!/usr/bin/bash

handle_termination() {
	if [ $? = 130 ]; then
		exit
	fi
}
handle_error() {
	STATUS=$?
	if [ $STATUS != 0 ]; then
		echo "$1: $STATUS"
		exit
	fi
}
get_text() {
	curl -kfs "$1"
	handle_termination
	handle_error "$2"
}
get_vanilla_download_url() {
	VERSION_MANIFEST_URL="https://launchermeta.mojang.com/mc/game/version_manifest.json"
	VERSION_MANIFEST=$(get_text "$VERSION_MANIFEST_URL" "Error getting version manifest from $VERSION_MANIFEST_URL")
	VERSION_ARRAY=$(jq -r .versions[].id <<<"$VERSION_MANIFEST")
	handle_error "Unable to parse versions from $VERSION_MANIFEST_URL"
	SELECTED_VERSION=$(gum filter --header "Vanilla Version" --value "$LATEST_RELEASE" <<<"$VERSION_ARRAY")
	handle_termination
	handle_error "Error selecting vanilla versions"
	DOWNLOAD_MANIFEST_URL="$(jq -r ".versions[] | select(.id == \"$SELECTED_VERSION\") | .url" <<<"$VERSION_MANIFEST")"
	handle_error "Unable to parse download manifest url from $VERSION_MANIFEST_URL"
	DOWNLOAD_MANIFEST=$(get_text "$DOWNLOAD_MANIFEST_URL" "Unable to curl $DOWNLOAD_MANIFEST_URL")
	DOWNLOAD_URL=$(jq -r ".downloads.server.url" <<<"$DOWNLOAD_MANIFEST")
	handle_error "Unable to parse download url from $DOWNLOAD_MANIFEST"
}
get_paper_download_url() {
	echo
}
get_tekkit_2_download_url() {
	echo
}
extract_server_files() {
	SERVER_FILES="$(pwd)/server_files"
	WORK_DIR="/app"
	CONTAINER_NAME="extract_${SELECTED_FLAVOR}_files"

	mkdir "$SERVER_FILES" &>/dev/null || (
		rm -rf "$SERVER_FILES"
		mkdir "$SERVER_FILES"
	)
	podman run \
		--volume "$SERVER_FILES:$WORK_DIR" \
		--workdir "$WORK_DIR" \
		--name "$CONTAINER_NAME" \
		docker.io/library/amazoncorretto:20 \
		/bin/sh -c "curl -kf $DOWNLOAD_URL --output server.jar && timeout 20 java -jar server.jar"
	if [ $? != 0 ]; then
		podman container rm "$CONTAINER_NAME"
		$(exit 1)
		handle_error "Error creating $CONTAINER_NAME container"
	fi

	podman container rm "$CONTAINER_NAME" || echo "Unable to delete container $CONTAINER_NAME"
}
deploy_image() {
	DEPLOY="$(gum filter --header "Where to deploy" <<<"$(printf "Don't\nLocalhost\nKubernetes")")"
	handle_termination
	handle_error "Error selecting where to deploy"

	if [ "$DEPLOY" = "Kubernetes" ]; then
		MINECRAFT_IMAGE_REPO="docker://$(gum input --placeholder docker.io/user/repo)"
		handle_termination
		handle_error "Error inputting user image repo"
		podman push localhost/minecraft:"$IMAGE_TAG" "$MINECRAFT_IMAGE_REPO":"$IMAGE_TAG"
		handle_termination
		handle_error "Unable to push localhost/minecraft:$IMAGE_TAG to $MINECRAFT_IMAGE_REPO"
		kubectl run -d "$IMAGE_TAG" --image "$MINECRAFT_IMAGE_REPO":"$IMAGE_TAG"
		handle_termination
		handle_error "Unable to run $IMAGE_TAG on kubernetes"
		kubectl port-forward "$IMAGE_TAG" 25565:25565
		handle_error "Unable to port-forward $IMAGE_TAG on kubernetes"
	elif [ "$DEPLOY" = "Localhost" ]; then
		podman run -d localhost/minecraft:"$IMAGE_TAG"
		echo "Local deploy SUCCESS"
	fi
}
main() {
	echo "Minecraft container creator"

	SELECTED_FLAVOR="$(gum filter --header "Server flavor" <<<"$(printf "Vanilla\nPaper\nTekkit 2")")"
	handle_termination
	handle_error "Error selecting server flavor"

	if [ "$SELECTED_FLAVOR" = "Vanilla" ]; then
		SELECTED_FLAVOR="vanilla"
		get_vanilla_download_url
		IMAGE_TAG="${SELECTED_FLAVOR}_$SELECTED_VERSION"
	elif [ "$SELECTED_FLAVOR" = "Paper" ]; then
		SELECTED_FLAVOR="paper"
		get_paper_download_url
		IMAGE_TAG="${SELECTED_FLAVOR}_${SELECTED_VERSION}_$SELECTED_BUILD"
	elif [ "$SELECTED_FLAVOR" = "Tekkit 2" ]; then
		SELECTED_FLAVOR="tekkit_2"
		get_tekkit_2_download_url
		IMAGE_TAG="${SELECTED_FLAVOR}_${SELECTED_VERSION}"
	fi

	extract_server_files

	echo
	echo "Configuration files are located in $SERVER_FILES"
	echo "Remove any generated world files and modify any configuration data you want"
	echo "Then run make_container.sh"
	echo
	read -p "Press Enter to continue..." </dev/tty
	echo

	echo "Downloading $IMAGE_TAG from $DOWNLOAD_URL"
	podman build . --tag minecraft:$IMAGE_TAG
	handle_termination
	handle_error "Unable to build image $IMAGE_TAG"

	deploy_image
}

main
