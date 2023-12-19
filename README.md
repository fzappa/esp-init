# esp-init

**ESP-IDF Project Creator Script**

This bash script simplifies the process of setting up new projects using the Espressif IoT Development Framework (ESP-IDF) for ESP32 chips. It automates cloning the ESP-IDF repository, creating new projects, and setting up the desired chip architecture.

## Features

- **Clone the ESP-IDF Repository**: Ensures the ESP-IDF is cloned and ready to use.
- **Create a New Project**: Quickly set up a new project with a specified name and chip architecture.
- **Set Chip Architecture**: Choose from various supported ESP32 architectures for your project.
- **Display Help**: Provides usage information and available options.

## Prerequisites

- Git must be installed to clone the ESP-IDF repository.
- ESP-IDF environment must be properly installed on your system.

## Usage

```bash
./script_name.sh [OPTION]
```

### Options

- `--clone`: Clone the ESP-IDF repository.
- `--new [project_name] [architecture]`: Create a new project. The architecture is optional (default is ESP32).
- `--help`: Display help information.

### Supported Architectures

- `esp32`
- `esp32s2`
- `esp32c3`
- `esp32s3`
- `esp32c2`
- `esp32c6`
- `esp32h2`
- `linux`
- `esp32p4`
- `esp32c5`

## Installation

1. Clone or download this script to your local machine.
2. Give execute permission to the script:
   ```bash
   chmod +x script_name.sh
   ```
3. Run the script with desired options.

## License

Distributed under the GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007. See `LICENSE` for more information.

---

```

```
