# FPGA-Based-USB-2.0-Controller

USB 2.0 Controller (Verilog RTL)

 Overview
This project implements a **USB 2.0 Host/Device Controller** in Verilog RTL, supporting key protocol operations such as token handling, data transfer, and handshake mechanisms. The design models low-level USB protocol behavior and demonstrates system-level understanding of USB communication.

---

Features
- USB 2.0 protocol implementation (Token, Data, Handshake phases)
- Enumeration FSM for device initialization
- PID (Packet Identifier) Encoder & Decoder
- CRC5 and CRC16 generation and checking
- NRZI Encoding and Decoding
- Bit Stuffing and Unstuffing logic
- ULPI Interface model for PHY communication (USB3300 compatible)
- Modular RTL design with scalable architecture

---

Architecture
The controller is divided into the following major blocks:

- **Protocol Engine**: Handles token, data, and handshake packet flow  
- **Enumeration FSM**: Manages device enumeration process  
- **PID Decoder/Encoder**: Identifies packet types  
- **CRC Generator/Checker**: Ensures data integrity  
- **NRZI Encoder/Decoder**: Implements USB physical layer encoding  
- **Bit Stuffing Module**: Maintains signal synchronization  
- **ULPI Interface**: Connects to external PHY for data transfer  

---

Working
1. Host initiates communication using **Token Packets (IN/OUT/SETUP)**  
2. Device responds with **Data Packets (DATA0/DATA1)**  
3. Handshake packets (**ACK/NAK/STALL**) ensure reliability  
4. Data is encoded using **NRZI encoding + Bit Stuffing** before transmission  
5. Receiver decodes and verifies data using **CRC5/CRC16**  
6. Enumeration FSM configures device during initialization phase  

---

Verification
- Developed testbench in **Verilog/SystemVerilog**
- Simulated using **ModelSim / QuestaSim**
- Verified:
  - Correct PID decoding
  - CRC validation
  - Bit stuffing/unstuffing behavior
  - FSM transitions during enumeration
- Performed **waveform analysis** for protocol correctness and edge cases  


## 🛠️ Tools Used
- ModelSim / QuestaSim (Simulation)
- Vivado / Quartus Prime (Synthesis-ready design)
- Git (Version Control)


Results
- Successful simulation of USB packet transactions
- Verified protocol compliance at functional level
- Stable data transmission with correct encoding/decoding
- Accurate FSM behavior during enumeration phase
```mermaid



