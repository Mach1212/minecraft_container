#!/usr/bin/bash

main() {
	echo "Minecraft container creator"

	SELECTED_FLAVOR="$(gum filter --header "Server flavor" <<<"$(printf "Vanilla\nPaper\nTekkit 2")")"
	handle_termination
	handle_error "Error selecting server flavor"

	if [ "$SELECTED_FLAVOR" = "Vanilla" ]; then
		SELECTED_FLAVOR="vanilla"
		get_vanilla_download_url
	elif [ "$SELECTED_FLAVOR" = "Paper" ]; then
		SELECTED_FLAVOR="paper"
		get_paper_download_url
	elif [ "$SELECTED_FLAVOR" = "Tekkit 2" ]; then
		SELECTED_FLAVOR="tekkit_2"
		get_tekkit_2_download_url
	fi

	extract_server_files
	exit
	podman build . --build-arg DOWNLOAD_URL=$DOWNLOAD_URL
}

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
	curl -kf "$1"
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

	echo "Downloading $SELECTED_FLAVOR:$SELECTED_VERSION from $DOWNLOAD_URL"
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

	mkdir "$WORK_DIR"
	podman run \
		--volume $SERVER_FILES:$WORK_DIR \
		--workdir $WORK_DIR \
		--name $CONTAINER_NAME \
		curl -kf $DOWNLOAD_URL --output server.jar

	podman cp "$CONTAINER_NAME:$WORK_DIR" "$SERVER_FILES"
	echo "Configuration files are located in $SERVER_FILES"
	echo "Remove any generated world files and modify any configuration data you want"
	echo "Then run make_container.sh"
}
main
