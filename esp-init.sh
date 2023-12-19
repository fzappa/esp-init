#!/bin/bash

# Initial settings
WORKDIR=~/esp/esp-projects
IDF_PATH=~/esp/esp-idf

# Function to clone ESP-IDF
clone_idf() {
    if [ ! -d "$IDF_PATH" ]; then
        echo "Cloning ESP-IDF..."
        git clone --recursive https://github.com/espressif/esp-idf.git $IDF_PATH
    else
        echo "ESP-IDF is already cloned."
    fi
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
    idf.py set-target $TARGET
    popd
}

# Function to create a new project
create_project() {
    PROJECT_NAME=$1
    TARGET=${2:-esp32}  # Set ESP32 as default if no target is specified
    PROJECT_DIR=$WORKDIR/$PROJECT_NAME

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
        
        # Load the environment
        source ~/esp/esp-idf/export.sh

        echo "Run 'cd $PROJECT_DIR' to change to the project directory."
    fi
}

# Function to display help
display_help() {
    echo "Usage: $0 [OPTION]"
    echo "Options:"
    echo "  --clone                 Clone the ESP-IDF repository."
    echo "  --new [project_name] [architecture]" 
    echo "                                       Create a new project with the"
    echo "                                      specified name and architecture" 
    echo "                                      (Default: esp32)."
    echo "esp32|esp32s2|esp32c3|esp32s3|esp32c2|esp32c6|esp32h2|linux|esp32p4|esp32c5"
    echo "  --help                  Display this help message."
}

# Check command line arguments
if [ $# -eq 0 ]; then
    display_help
    exit 1
fi

case "$1" in
    --clone)
        clone_idf
        ;;
    --new)
        if [ $# -lt 2 ]; then
            echo "Error: Project name not specified."
            exit 1
        fi
        create_project "$2" "$3"
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
