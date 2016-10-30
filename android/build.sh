# !/bin/bash
# Copyright Pristine Inc 
# Author: Rahul Behera <rahul@pristine.io>
# Author: Aaron Alaniz <aaron@pristine.io>
# Author: Arik Yaacob   <arik@pristine.io>
#
# Builds the android peer connection library

# Get location of the script itself .. thanks SO ! http://stackoverflow.com/a/246128
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
PROJECT_ROOT="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# Utility method for creating a directory
create_directory_if_not_found() {
	# if we cannot find the directory
	if [ ! -d "$1" ];
		then
		echo "$1 directory not found, creating..."
	    mkdir -p "$1"
	    echo "directory created at $1"
	fi
}

USER_WEBRTC_URL="git@github.com:notedit/dotEngine-webrtc-mirror.git"
DEFAULT_WEBRTC_URL="https://chromium.googlesource.com/external/webrtc"
DEPOT_TOOLS="$PROJECT_ROOT/depot_tools"
WEBRTC_ROOT="$PROJECT_ROOT/webrtc"
create_directory_if_not_found "$WEBRTC_ROOT"
BUILD="$WEBRTC_ROOT/libjingle_peerconnection_builds"
WEBRTC_TARGET="libjingle_peerconnection_so"

WEBRTC_TARGET_JAR="libjingle_peerconnection_java"

ANDROID_TOOLCHAINS="$WEBRTC_ROOT/src/third_party/android_tools/ndk/toolchains"



WEBRTC_JAR="$WEBRTC_ROOT/src/webrtc/api/android/java/src/org/webrtc"

WEBRTC_JAR_VOICE_ENGINE="$WEBRTC_ROOT/src/webrtc/modules/audio_device/android/java/src/org/webrtc/voiceengine"



exec_ninja() {
  echo "Running ninja"
  ninja -C $1  $WEBRTC_TARGET
  ninja -C $1  $WEBRTC_TARGET_JAR
}

# Installs the required dependencies on the machine
install_dependencies() {
    sudo apt-get -y install wget git gnupg flex bison gperf build-essential zip curl subversion pkg-config libglib2.0-dev libgtk2.0-dev libxtst-dev libxss-dev libpci-dev libdbus-1-dev libgconf2-dev libgnome-keyring-dev libnss3-dev
    #Download the latest script to install the android dependencies for ubuntu
    curl -o install-build-deps-android.sh https://src.chromium.org/svn/trunk/src/build/install-build-deps-android.sh
    #use bash (not dash which is default) to run the script
    sudo /bin/bash ./install-build-deps-android.sh
    #delete the file we just downloaded... not needed anymore
    rm install-build-deps-android.sh
}

# Update/Get/Ensure the Gclient Depot Tools
# Also will add to your environment
pull_depot_tools() {
	WORKING_DIR=`pwd`

    # Either clone or get latest depot tools
	if [ ! -d "$DEPOT_TOOLS" ]
	then
	    echo Make directory for gclient called Depot Tools
	    mkdir -p "$DEPOT_TOOLS"

	    echo Pull the depo tools project from chromium source into the depot tools directory
	    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $DEPOT_TOOLS

	else
		echo Change directory into the depot tools
		cd "$DEPOT_TOOLS"

		echo Pull the depot tools down to the latest
		git pull
	fi
	PATH="$PATH:$DEPOT_TOOLS"

    # Navigate back
	cd "$WORKING_DIR"
}

# Update/Get the webrtc code base
pull_webrtc() {
    WORKING_DIR=`pwd`

    # If no directory where webrtc root should be...
    create_directory_if_not_found "$WEBRTC_ROOT"
    cd "$WEBRTC_ROOT"

    # Setup gclient config
    echo Configuring gclient for Android build
    if [ -z $USER_WEBRTC_URL ]
    then
        echo "User has not specified a different webrtc url. Using default"
        gclient config --name=src "$DEFAULT_WEBRTC_URL"
    else
        echo "User has specified their own webrtc url $USER_WEBRTC_URL"
        gclient config --name=src "$USER_WEBRTC_URL"
    fi

    # Ensure our target os is correct building android
	echo "target_os = ['unix', 'android']" >> .gclient

    # Get latest webrtc source
	echo Pull down the latest from the webrtc repo
	echo this can take a while
	if [ -z $1 ]
    then
        echo "gclient sync with newest"
        gclient sync
    else
        echo "gclient sync with $1"
        gclient sync -r $1
    fi

    # Navigate back
	cd "$WORKING_DIR"
}



# Setup our defines for the build
prepare_gyp_defines() {
    # Configure environment for Android
    echo Setting up build environment for Android
    source "$WEBRTC_ROOT/src/build/android/envsetup.sh"
}

# Builds the apprtc demo
execute_build() {
    WORKING_DIR=`pwd`
    cd "$WEBRTC_ROOT/src"

    echo Run gclient hooks
    gclient runhooks

    if [ "$WEBRTC_ARCH" = "x86" ] ;
    then
        gn gen out_android_x86/Release --args='target_os="android" target_cpu="x86" is_debug=false  is_component_build=false'
    elif [ "$WEBRTC_ARCH" = "x64" ] ;
    then
        gn gen out_android_x64/Release --args='target_os="android" target_cpu="x64" is_debug=false  is_component_build=false'
    elif [ "$WEBRTC_ARCH" = "arm" ] ;
    then
        gn gen out_android_arm/Release --args='target_os="android" target_cpu="arm" dcheck_always_on=true symbol_level=1 is_debug=false  is_component_build=false'
    elif [ "$WEBRTC_ARCH" = "arm64" ] ;
    then
        gn gen out_android_arm64/Release --args='target_os="android" target_cpu="arm64" is_debug=false  is_component_build=false'
    fi

    if [ "$WEBRTC_DEBUG" = "true" ] ;
    then
        BUILD_TYPE="Debug"
    else
        BUILD_TYPE="Release"
    fi

    ARCH_OUT="out_android_${WEBRTC_ARCH}"
    echo "Build ${WEBRTC_TARGET} in $BUILD_TYPE (arch: ${WEBRTC_ARCH:-arm})"
    exec_ninja "$ARCH_OUT/$BUILD_TYPE"
    
    # Verify the build actually worked
    if [ $? -eq 0 ]; then
        SOURCE_DIR="$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE"
        TARGET_DIR="$BUILD/$BUILD_TYPE"
        create_directory_if_not_found "$TARGET_DIR"
        
        echo "Copy JAR File"
        create_directory_if_not_found "$TARGET_DIR/libs/"
        create_directory_if_not_found "$TARGET_DIR/jni/"

        ARCH_JNI="$TARGET_DIR/jni/${WEBRTC_ARCH}"
        create_directory_if_not_found "$ARCH_JNI"

        # Copy the jar
        #cp -p "$SOURCE_DIR/lib.java/webrtc/api/libjingle_peerconnection_java.jar" "$TARGET_DIR/libs/libjingle_peerconnection.jar"
        #cp -p "$SOURCE_DIR/lib.java/webrtc/base/base_java.jar" "$TARGET_DIR/libs/base_java.jar"

        cp -rf $WEBRTC_JAR  "$TARGET_DIR/libs/"
        cp -rf $WEBRTC_JAR_VOICE_ENGINE "$TARGET_DIR/libs/"

        cp -p "$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE/"*.so "$ARCH_JNI/"

        cd "$TARGET_DIR"

        cd "$WORKING_DIR"
        echo "$BUILD_TYPE build for apprtc complete"
    else
        
        echo "$BUILD_TYPE build for apprtc failed"
        #exit 1
    fi
}


get_webrtc() {
    pull_depot_tools &&
    pull_webrtc $1
}

# Updates webrtc and builds apprtc
build_apprtc() {
    export WEBRTC_ARCH=arm
    prepare_gyp_defines &&
    execute_build

    export WEBRTC_ARCH=arm64
    prepare_gyp_defines &&
    execute_build

    export WEBRTC_ARCH=x86
    prepare_gyp_defines &&
    execute_build

    export WEBRTC_ARCH=x64
    prepare_gyp_defines &&
    execute_build
}
