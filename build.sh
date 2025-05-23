#!/bin/sh
set -e

# Debug mode
if [ "${GITHUB_REPOSITORY}" = "engineersmith/love-build" ]; then
    set -x
fi

check_environment() {
    : "${INPUT_APP_NAME:?'Error: application name unset'}"
    : "${INPUT_LOVE_VERSION:?'Error: love version unset'}"
    # Check for presence of main.lua
    if [ ! -f "${SOURCE_DIR}/main.lua" ]; then
        echo "Error: Cannot find main.lua in the specified source directory"
        exit 1
    fi
}

# Fetches the love binaries from GitHub, takes architecture (macos/win32/win64)
# as an argument.
get_love_binaries() {
    glb_arch=$1
    glb_root_url="https://github.com/love2d/love/releases/download"
    if [ ${INPUT_LOVE_VERSION} != "12.0" ]; then
        wget "${glb_root_url}/${INPUT_LOVE_VERSION}/love-${INPUT_LOVE_VERSION}-${glb_arch}.zip"
    else
        mv "/love-build/love-${INPUT_LOVE_VERSION}-${glb_arch}.zip" .
    fi
    unzip "love-${INPUT_LOVE_VERSION}-${glb_arch}.zip" 
    rm "love-${INPUT_LOVE_VERSION}-${glb_arch}.zip" 
}

# Exports a .love file for the application to the path specified as an
# argument. e.g 
#     build_lovefile /path/to/new/lovefile.love
# Dependencies are handled via luarocks, if the INPUT_DEPENDENCIES
# environmental variable is set, we use luarocks to install a local rocks
# tree to `lb_modules` and insert this path into the love require path.
build_lovefile(){
    blf_target=$1
    blf_build_dir=$(mktemp -d -t love-build-XXXXXX)
    cp -a "${SOURCE_DIR}/." "${blf_build_dir}"
    (
        # Change to build dir (subshell to preserve cwd)
        cd "${blf_build_dir}" 
        # If the specified dependency file exists, use it 
        if [ -n "${INPUT_DEPENDENCIES}" ]; then
            depsfile="${GITHUB_WORKSPACE}/${INPUT_DEPENDENCIES}"
            # Build the dependencies into a local luarocks tree
            luarocks make "${depsfile}" --deps-mode one --lua-version=5.1 --tree lb_modules 
            # Add custom require paths
            cat /love-build/module_loader.lua main.lua > new_main.lua
            mv new_main.lua main.lua
        fi
        zip -r "application.love" ./* -x '*.git*' "${INPUT_RESULT_DIR}/*"
    )
    mv "${blf_build_dir}/application.love" "${blf_target}"
    rm -rf "${blf_build_dir}"
}

# Exports a zipped macOS application to the result directory.
build_macos(){
    bm_target="${INPUT_APP_NAME}_macos"
    bm_build_dir=$(mktemp -d -t love-build-XXXXXX)
    build_lovefile "${bm_build_dir}/application.love"
    (
        # Change to build dir (subshell to preserve cwd)
        cd "${bm_build_dir}" 
        
        # Download love for macos
        # Older (pre v11) labelled this as "macosx-x64" or "macosx-ub"
        get_love_binaries "macos" || get_love_binaries "macosx-x64" || get_love_binaries "macosx-ub"

        # Copy Data
        cp "application.love" "love.app/Contents/Resources/"
        # If a plist file is provided, use that
        if [ -f "${SOURCE_DIR}/Info.plist" ]; then
            cp "${SOURCE_DIR}/Info.plist" "love.app/Contents/"
        fi

        # Setup final archives
        mv "love.app" "${bm_target}.app"
        zip -ry "${bm_target}.zip" "${bm_target}.app"
    )
    mv "${bm_build_dir}/${bm_target}.zip" "${RESULT_DIR}"
    echo "macos-filename=${INPUT_RESULT_DIR}/${bm_target}.zip" >> $GITHUB_OUTPUT
    rm -rf "${bm_build_dir}"
}

# Exports a zipped win32 application to the result directory.
# Takes the architecure as an argument (win32/win64)
build_windows(){
    bw_arch=$1
    bw_target="${INPUT_APP_NAME}_${bw_arch}"
    bw_build_dir=$(mktemp -d -t love-build-XXXXXX)
    build_lovefile "${bw_build_dir}/application.love"
    (
        # Change to build dir (subshell to preserve cwd)
        cd "${bw_build_dir}" 

        # Fetch the appropriate binaries
        case $bw_arch in
          win32)
            get_love_binaries "win32" || get_love_binaries "win-x86"
            ;;
        
          win64)
            get_love_binaries "win64" || get_love_binaries "win-x64"
            ;;
        esac

        # Get unpacked directory name (can vary a bit, e.g 11.4, 11.2.0) and rename
        love_dir=$(find . -type d -regex ".*/love-.*" | head -n1)
        mv "${love_dir}" "${bw_target}"

        # Copy data
        cat "${bw_target}/love.exe" "application.love" > "${bw_target}/${INPUT_APP_NAME}.exe"
        # Delete unneeded files
        rm "${bw_target}/love.exe"
        rm "${bw_target}/lovec.exe" || true
        rm "${bw_target}/love.ico" || true
        rm "${bw_target}/changes.txt" || true
        rm "${bw_target}/readme.txt" || true

        # Setup final archive
        zip -ry "${bw_target}.zip" "${bw_target}"
    )
    mv "${bw_build_dir}/${bw_target}.zip" "${RESULT_DIR}"/
    echo "${bw_arch}-filename=${INPUT_RESULT_DIR}/${bw_target}.zip" >> $GITHUB_OUTPUT
    rm -rf "${bw_build_dir}"
}

main() {

    echo "-- LOVE build parameters --"
    echo "App name: ${INPUT_APP_NAME}"
    echo "LOVE version: ${INPUT_LOVE_VERSION}"
    echo "---------------------------"
    echo "Source directory: ${INPUT_SOURCE_DIR}"
    echo "Result directory: ${INPUT_RESULT_DIR}"
    echo "---------------------------"

    # Append workspace dir to relevant paths
    SOURCE_DIR=${GITHUB_WORKSPACE}/${INPUT_SOURCE_DIR}
    RESULT_DIR=${GITHUB_WORKSPACE}/${INPUT_RESULT_DIR}
    
    check_environment
    
    # Make results directory if it does not exist
    mkdir -p "${RESULT_DIR}"
    
    ### LOVE build ####################################################
    
    build_lovefile "${RESULT_DIR}/${INPUT_APP_NAME}.love"
    echo "love-filename=${INPUT_RESULT_DIR}/${INPUT_APP_NAME}.love" >> $GITHUB_OUTPUT
    
    ### macOS/win builds ##############################################
    
    build_macos
    # build_windows "win32"; # removed support for win32
    build_windows "win64";

}


main "$@"
