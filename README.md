# RISC-V
RISC-V CPU implementation using BSV (BlueSpec Verilog)

This repo has some basic function implementation and RISC-V implementation using BSV.     
Also it has the solution for the famous bomb lab (by CMU) for Computer Architecture.     
You can test the RISC-V implementation by compiling as ./risc-v -c and executing by ./risc-v -r.     

The materials and labs are from SNU Computer Architecture (2025 Spring).     
The rough explanations for the labs are provided below.

## Lab explanation
### Lab0
Implementing Basic functions like HelloWorld in BSV.

### Lab1
Implementing a barrel shifter in BSV using multiplexers.

### Lab2
Implementing a pipelined barrel shifter.

### Lab3
Implementing an FFT algorithm in 2 ways (Folded, Pipelined)

### Lab4
Intro to implementation of RISC-V. Implementing a non-pipelined, four cycle RISC-V CPU.

### Lab5
Implementing a 3-stage pipelined RISC-V CPU, by solving control hazards using epoch.

### Lab6
Implementing a 5-stage pipelined RISC-V CPU, by solving control hazards using epoch and solving data hazards by scoreboard.(lab6-1)         
lab6-2 is the same, but solves data hazards by forwarding.

### Lab7
Implementing a 3-stage pipelined RISC-V CPU using local cache. We check the miss rate and # of cycles decrease as we increase the block size and the associativity.
