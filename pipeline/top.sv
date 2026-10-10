//////////////////////////////////////////////////////////////////////////// 
// ======================================================================== 
// This file has the following module implementations: 
// 1. top 
// 2. mips 
// 3. dmem 
// 4. imem 
// ========================================================================= 
//////////////////////////////////////////////////////////////////////////// 
// Top Module  
//  - This module connects the MIPS processor to instruction and data memory 
//////////////////////////////////////////////////////////////////////////// 

// Add Enums for opcode and funct fields to make debug easier
typedef enum logic [5:0] {
    OP_RTYPE = 6'b000000,
    OP_LW    = 6'b100011,
    OP_SW    = 6'b101011,
    OP_BEQ   = 6'b000100,
    OP_ADDI  = 6'b001000,
    OP_J     = 6'b000010,
    OP_PERF  = 6'b111111
} opcode_t;

typedef enum logic [5:0] {
    FUNCT_ADD  = 6'b100000,
    FUNCT_SUB  = 6'b100010,
    FUNCT_AND  = 6'b100100,
    FUNCT_OR   = 6'b100101,
    FUNCT_SLT  = 6'b101010,
    FUNCT_MAC  = 6'b100001,
    FUNCT_PERF_CYC = 6'b000000,
    FUNCT_PERF_INST = 6'b000001
} funct_t;
// ============================================================
// Top-level processor and memory connections
// ============================================================
module top (
    input  logic        clk, reset,
    output logic [31:0] writedata, dataadr,
    output logic        memwrite
);

    logic [31:0] pc, instr, readdata;

    mips mips ( .aluout(dataadr), .*);

    imem imem (
        .a(pc[7:2]),
        .rd(instr)
    );

    dmem dmem (
        .clk(clk),
        .we(memwrite),
        .a(dataadr),
        .wd(writedata),
        .rd(readdata)
    );

endmodule


// ============================================================
// Five-stage MIPS processor
// ============================================================
module mips (
    input  logic        clk, reset,
    output logic [31:0] pc,
    input  logic [31:0] instr,
    output logic        memwrite,
    output logic [31:0] aluout, writedata,
    input  logic [31:0] readdata
);

    logic [31:0] instrD;

    logic memtoregD, memwriteD, branchD;
    logic alusrcD, regdstD, regwriteD, jumpD;
    logic [2:0] alucontrolD;

    // Decode the instruction held in the Decode stage.
    controller c (
        .op(opcode_t'(instrD[31:26])),
        .funct(funct_t'(instrD[5:0])),
        .*
    );

    datapath dp ( .* );

endmodule


// ============================================================
// Data memory: 64 words, asynchronous read, synchronous write
// ============================================================
module dmem (
    input  logic        clk, we,
    input  logic [31:0] a, wd,
    output logic [31:0] rd
);

    logic [31:0] RAM [0:63];

    assign rd = RAM[a[7:2]];

    always_ff @(posedge clk) begin
        if (we)
            RAM[a[7:2]] <= wd;
    end

endmodule


// ============================================================
// Instruction memory: 64 words loaded from memfile.dat
// ============================================================
module imem (
    input  logic [5:0]  a,
    output logic [31:0] rd
);

    logic [31:0] RAM [0:63];

    initial begin
        // Fill unused locations with NOPs.
        for (int i = 0; i < 64; i++)
            RAM[i] = 32'b0;

        $readmemh("memfile.dat", RAM);
    end

    assign rd = RAM[a];

endmodule