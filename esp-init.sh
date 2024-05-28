#!/bin/bash

# Initial settings
WORKDIR=~/esp/esp-projects
IDF_PATH=~/esp/esp-idf

# Function to check if Git is installed
check_git() {
    if ! command -v git &>/dev/null; then
        echo "Git is not installed. Please install Git and try again."
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    sudo apt-get update
    sudo apt-get install -y git wget flex bison gperf python3 python3-pip python3-venv cmake ninja-build ccache libffi-dev libssl-dev dfu-util libusb-1.0-0
}

# Function to clone ESP-IDF
clone_idf() {
    if [ ! -d "$IDF_PATH" ]; then
        echo "Cloning ESP-IDF..."
        git clone --recursive https://github.com/espressif/esp-idf.git $IDF_PATH
    else
        echo "ESP-IDF is already cloned."
    fi
}

# Function to set up the tools for specified architectures
setup_tools() {
    ARCHITECTURES=${1:-esp32} # Set ESP32 as default if no architectures are specified

    pushd $IDF_PATH
    ./install.sh $ARCHITECTURES
    popd
}

# Function to update CMakeLists.txt
update_cmake_lists() {
    PROJECT_DIR=$1
    PROJECT_NAME=$2

    # Replace the project line in CMakeLists.txt
    sed -i "s/project(hello_world)/project(${PROJECT_NAME})/" $PROJECT_DIR/CMakeLists.txt
    sed -i "s/hello_world_main/main/" $PROJECT_DIR/main/CMakeLists.txt
}

# Function to set the chip architecture
set_target() {
    PROJECT_DIR=$1
    TARGET=$2

    # Change to the project directory and set the target
    pushd $PROJECT_DIR

    # Load the environment
    source ~/esp/esp-idf/export.sh

    idf.py set-target $TARGET
    popd
}

# Function to create a new project
create_project() {
    PROJECT_NAME=$1
    TARGET=${2:-esp32} # Set ESP32 as default if no target is specified
    PROJECT_DIR=$WORKDIR/$PROJECT_NAME

    # Check if IDF_PATH exists
    if [ ! -d "$IDF_PATH" ]; then
        echo "Error: IDF_PATH directory does not exist. Please set up IDF_PATH correctly."
        exit 1
    fi

    # Check if PROJECT_DIR exists
    if [ -d "$PROJECT_DIR" ]; then
        echo "A project with this name already exists."
        exit 1
    else
        mkdir -p $PROJECT_DIR
        cp -r $IDF_PATH/examples/get-started/hello_world/* $PROJECT_DIR
        echo "Project $PROJECT_NAME created at $PROJECT_DIR."

        # Rename the main file and update CMakeLists.txt
        mv $PROJECT_DIR/main/hello_world_main.c $PROJECT_DIR/main/main.c
        update_cmake_lists $PROJECT_DIR $PROJECT_NAME

        # Set the chip architecture
        set_target $PROJECT_DIR $TARGET

        echo "Run 'cd $PROJECT_DIR' to change to the project directory."
    fi
}

# Function to display help
display_help() {
    echo "Usage: $0 [OPTION]"
    echo "Options:"
    echo "  --clone [architectures] Clone the ESP-IDF repository and set up the tools for the specified architectures (default: esp32)."
    echo "                          Architectures should be separated by commas (e.g., esp32,esp32s3)."
    echo "  --new [project_name] [architecture]"
    echo "                                       Create a new project with the"
    echo "                                       specified name and architecture"
    echo "                                       (Default: esp32)."
    echo "                                       Available architectures: esp32, esp32s2, esp32c3, esp32s3, esp32c2, esp32c6, esp32h2, linux, esp32p4, esp32c5."
    echo "  --install-deps          Install necessary dependencies on Ubuntu."
    echo "  --help                  Display this help message."
    echo ""
    echo "Examples:"
    echo "  Clone ESP-IDF and set up tools for esp32:"
    echo "    $0 --clone"
    echo ""
    echo "  Clone ESP-IDF and set up tools for esp32 and esp32s3:"
    echo "    $0 --clone esp32,esp32s3"
    echo ""
    echo "  Create a new project named 'my_project' for esp32:"
    echo "    $0 --new my_project esp32"
    echo ""
    echo "  Install necessary dependencies:"
    echo "    $0 --install-deps"
}

# Check command line arguments
if [ $# -eq 0 ]; then
    display_help
    exit 1
fi

# Check if Git is installed
check_git

case "$1" in
--clone)
    clone_idf
    if [ -n "$2" ]; then
        setup_tools "$2"
    else
        setup_tools
    fi
    ;;
--new)
    if [ $# -lt 2 ]; then
        echo "Error: Project name not specified."
        exit 1
    fi
    create_project "$2" "$3"
    ;;
--install-deps)
    install_dependencies
    ;;
--help)
    display_help
    ;;
*)
    echo "Invalid option: $1"
    display_help
    exit 1
    ;;
esac
