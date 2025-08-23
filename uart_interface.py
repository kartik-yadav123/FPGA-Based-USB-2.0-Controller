import serial
import serial.tools.list_ports
import time
import os

# Path to the main project folder
DATA_FOLDER = r"C:\Users\Kartik\Desktop\usb_protocal_implementation"

# Create the folder if it doesn't exist
if not os.path.exists(DATA_FOLDER):
    print(f"Creating data folder: '{DATA_FOLDER}'")
    os.makedirs(DATA_FOLDER)

def list_serial_ports():
    """Lists available serial ports."""
    ports = serial.tools.list_ports.comports()
    if not ports:
        print("No serial ports found. Please ensure your USB-to-serial adapter is connected.")
        return []
    print("Available serial ports:")
    for port, desc, hwid in sorted(ports):
        print(f"  - {port}: {desc}")
    return ports

def get_file_path(filename):
    """
    Checks for .bin and .bin.txt versions of the file.
    If .bin.txt exists but .bin doesn't, it renames it automatically.
    """
    bin_path = os.path.join(DATA_FOLDER, filename)
    txt_path = bin_path + ".txt"

    if os.path.exists(bin_path):
        return bin_path

    if os.path.exists(txt_path):
        print(f"Found '{txt_path}', renaming to '{bin_path}'...")
        os.rename(txt_path, bin_path)
        return bin_path

    return bin_path  # Will be used for saving new files

def read_from_fpga(port, baudrate, filename, timeout=5):
    """Read data from FPGA via serial and save to file."""
    file_path = get_file_path(filename)
    print(f"Attempting to open serial port '{port}'...")
    try:
        ser = serial.Serial(port, baudrate, timeout=timeout)
        print(f"Serial port '{port}' opened successfully. Baud rate: {baudrate}")
        print(f"Reading from FPGA and writing to file '{file_path}'...")
        
        with open(file_path, 'wb') as f:
            total_bytes = 0
            while True:
                data = ser.read()
                if not data:
                    print("\nTimeout: End of data transmission assumed.")
                    break
                f.write(data)
                total_bytes += len(data)
                print(f"\rBytes received: {total_bytes}", end="", flush=True)

        print(f"\nRead complete. Total bytes written: {total_bytes}")

    except serial.SerialException as e:
        print(f"Error: Could not open serial port '{port}': {e}")
    except FileNotFoundError:
        print(f"Error: Could not open file '{file_path}'.")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print(f"Serial port '{port}' closed.")

def write_to_fpga(port, baudrate, filename):
    """Send file data to FPGA via serial."""
    file_path = get_file_path(filename)
    print(f"Attempting to open serial port '{port}'...")
    try:
        if not os.path.exists(file_path):
            print(f"Error: The file '{file_path}' was not found.")
            return

        ser = serial.Serial(port, baudrate, timeout=1)
        print(f"Serial port '{port}' opened successfully. Baud rate: {baudrate}")
        print(f"Reading from file '{file_path}' and writing to FPGA...")

        with open(file_path, 'rb') as f:
            total_bytes = 0
            while True:
                chunk = f.read(1024)
                if not chunk:
                    break
                ser.write(chunk)
                total_bytes += len(chunk)
                print(f"\rBytes sent: {total_bytes}", end="", flush=True)

        print(f"\nWrite complete. Total bytes sent: {total_bytes}")
        time.sleep(1)

    except serial.SerialException as e:
        print(f"Error: Could not open serial port '{port}': {e}")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print(f"Serial port '{port}' closed.")

if __name__ == "__main__":
    SERIAL_PORT = 'COM3'
    BAUD_RATE = 115200

    list_serial_ports()
    print("-" * 50)

    # Read from FPGA
    output_filename = 'data_from_fpga.bin'
    print("Starting READ operation:")
    read_from_fpga(SERIAL_PORT, BAUD_RATE, output_filename)
    print("-" * 50)

    # Write to FPGA
    input_filename = 'data_to_fpga.bin'
    print("Starting WRITE operation:")
    write_to_fpga(SERIAL_PORT, BAUD_RATE, input_filename)
