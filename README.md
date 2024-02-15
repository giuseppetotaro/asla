# Apple Silicon Logical Acquisition Script

The Apple Silicon Logical Acquisition (ASLA) script in this repository is a bash script called `asla.sh` designed for performing forensically-sound logical acquisition of Apple Silicon Mac devices. This script facilitates the collection of data from an Apple Silicon Mac in a manner that maintains the integrity of the original data, ensuring that the acquisition process complies with forensic standards.

## Description

### Getting started

`% ./asla.sh /path/to/target /path/to/destination`

### Procedure

* _Host_: the Mac device used for the acquisition, where the script is executed;
* _Target_: the Mac device to be acquired, started in share disk mode.

1. Target must be started in Recovery Mode (press and hold power button)
2. Selecting Options opens Recovery
3. Select Utilities > Share Disk to start sharing
4. If the volume is locked by File Vault, it must be locked (you need a user's name and password)
5. Host must be turned on and connected to power charger before connecting to Target
6. Power supply to Target should be provided only after connecting to the Host (it has been experienced that an Apple Silicon Mac is not seen if it is already connected to the power supply)
7. Connect from a USB-C port on the Target to a USB-C port on the Host via a cable TB3 (USB-C) - TB3 (USB-C)
8. You should hear a sound which means that Target is connected to Host
9. Connect Target with power supply
10. Open Finder > Go > Network and check if you see Target's name (e.g., MacBook Air)

## Installation

This script can be executed in Terminal and would not need any specific software besides those already provided in macOS.
However, it is highly recommended that you have the [Xcode Command Line Tools](https://developer.apple.com/xcode/) installed on your system.

To install the Xcode Command Line Tools, you can enter the command `xcode-select --install` in the Terminal.

This script has been tested on macOS Sonoma (Version 14.3) with the Xcode Command Line Tools installed.

## Usage

`% ./asla.sh -h`

```
  Usage:  ./asla.h target destination [-a] [-c] [-i image_name] [-s size] [-u utility]

  target                      path to the target (i.e., the mount point of the Mac's shared disk to be acquired)
  destination                 path to the folder where the destination sparse image will be created

  If the target is a path to a non-existing folder, the script will run in assisted mode (equivalent to using the -a option).

  Options:
    -h, --help                print this help message
    -a, --assisted            run the script in assisted mode to identify the target
    -c, --calculate-hash      calculate MD5 and SHA1 hashes of the sparse image
    -i, --image-name <name>   name of the sparse image (without .sparseimage extension)
    -s, --size <number>       size of the sparse image in GigaBytes (default is 1000)
    -u, --utility <cp|rsync>  utility for the acquisition (cp or rsync; cp is the default)
```

## Contributing

Contributions to this project are welcome! If you encounter any issues, have suggestions for improvements, or would like to contribute new features, please feel free to submit a pull request or open an issue on GitHub.

## Authors and Acknowledgments

This script was developed by Giuseppe Totaro based on extensive experience in the field of digital forensics.

Special thanks to the following colleagues for their invaluable insights, feedback, and testing contributions:

- Israel Gordillo Torres
- Francesco Cappotto
- Sammy Nieuwborg

Their expertise and dedication greatly enhanced the quality and reliability of this script.

## License

This project is licensed under the [MIT License](LICENSE). Feel free to modify and distribute the script according to the terms of this license.
