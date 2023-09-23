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
	while true; do
		if [ -z "$SELECTED_VERSION" ]; then 
	    VERSION_ARRAY="$(jq -r '.versions[] | select(.type=="release") | .id' <<<"$VERSION_MANIFEST")"
	    handle_error "Unable to parse versions from $VERSION_MANIFEST_URL"
		else
	    VERSION_ARRAY="$(jq -r '.versions[].id' <<<"$VERSION_MANIFEST")\nDisplay all options"
		fi
	  SELECTED_VERSION=$(gum filter --header "Vanilla Version" --value "$LATEST_RELEASE" <<<"$(printf "$VERSION_ARRAY")")
	  handle_termination
	  handle_error "Error selecting vanilla versions"
	  if [ $SELECTED_VERSION != "Display all options" ]; then
	  	break
	  fi
	done
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
delete_logs() {
	LOG_PATHS=$(find "$SERVER_FILES" -name "*.log")
	if [ -n "$LOG_PATHS" ]; then
	  rm -rf $LOG_PATHS
	fi
}
accept_eula() {
	EULA_PATH=$(find "$SERVER_FILES" -name "eula.txt")
	if [ -n "$EULA_PATH" ] && gum confirm "Accept Mojangs eula?"; then
		sed -i 's/false/true/' "$EULA_PATH"
    handle_error "Unable to change eula from false to true"
	fi
}
process_server_files() {
	delete_logs
	accept_eula
}
push_image_to_repo() {
	if gum confirm "Push image to repo?"; then
		MINECRAFT_IMAGE_REPO="$(gum input --placeholder docker.io/user/repo)"
		handle_termination
		handle_error "Error inputting user image repo"
		while ! podman login "$MINECRAFT_IMAGE_REPO"; do
			${}
		done
		podman push localhost/minecraft:"$IMAGE_TAG" "docker://$MINECRAFT_IMAGE_REPO":"$IMAGE_TAG"
		if [ $? != 0 ]; then
			echo "Unable to push localhost/minecraft:$IMAGE_TAG to $MINECRAFT_IMAGE_REPO"
			MINECRAFT_IMAGE_REPO=''
		fi
	fi
}
deploy_image() {
	DEPLOY_OPTIONS="Don't\nLocalhost"
	if ! test -z "$MINECRAFT_IMAGE_REPO"; then
		DEPLOY_OPTIONS="$DEPLOY_OPTIONS\nKubernetes"
	fi
	DEPLOY="$(gum filter --header "Where to deploy" <<<"$(printf "$DEPLOY_OPTIONS")")"
	handle_termination
	handle_error "Error selecting where to deploy"

	if [ "$DEPLOY" = "Kubernetes" ]; then
		POD_NAME="$(tr '_.' '-' <<<"$IMAGE_TAG")-$(tr ':' '.' <<<"$(date '+%x-%X')")"
		kubectl run "$POD_NAME" --image "$MINECRAFT_IMAGE_REPO":"$IMAGE_TAG"
		handle_termination
		handle_error "Unable to run $IMAGE_TAG on kubernetes"
		echo "Kube deploy SUCCESS"
		if gum confirm "Attach to pod?"; then
			printf "\nAttaching..."
		  if ! kubectl attach "$POD_NAME"; then 
				printf "\nFailed attaching...\n\nLogs:\n"
				kubectl logs "$POD_NAME"
		  fi
		fi
	elif [ "$DEPLOY" = "Localhost" ]; then
		podman run -d localhost/minecraft:"$IMAGE_TAG"
		handle_error "Unable to run Minecraft container"
		echo "Local deploy SUCCESS"
		if gum confirm "Attach to container?"; then
			printf "\nAttaching..."
			podman attach --latest
		fi
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
	process_server_files

	echo
	echo "Configuration files are located in $SERVER_FILES"
	echo "Remove any generated world files and modify any configuration data you want"
	echo
	read -p "Press Enter to continue..." </dev/tty
	echo

	echo "Downloading $IMAGE_TAG from $DOWNLOAD_URL"
	podman build . --tag minecraft:$IMAGE_TAG
	handle_termination
	handle_error "Unable to build image $IMAGE_TAG"

	# detect eula and fix
	# vanilla show only release versions unless all is selected
	# paper
	# tekkit 2
	# runtime args
	# Check dependencies before running

	push_image_to_repo
	deploy_image
}

main
