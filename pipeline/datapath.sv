////////////////////////////////////////////////////////////////////// 
// =================================================================== 
// This file has the following module implementations: 
// 1. datapath 
// 2. regfile 
// 3. alu 
// 4. adder 
// 5. mux2 
// 6. sl2 
// 7. signext 
// 8. flopr 
// =================================================================== 
////////////////////////////////////////////////////////////////////// 
// Datapath module 
////////////////////////////////////////////////////////////////////// 

module datapath (
    input  logic        clk, reset,

    // Controls from the Decode-stage controller
    input  logic        D_memtoreg, D_memwrite, D_branch,
    input  logic        D_alusrc, D_regdst, D_regwrite, D_jump,
    input  logic [2:0]  D_alucontrol,

    // Instruction memory interface
    output logic [31:0] pc,
    input  logic [31:0] instr,
    output logic [31:0] D_instr,

    // Data memory interface
    output logic        memwrite,
    output logic [31:0] aluout, writedata,
    input  logic [31:0] readdata
);

    // Instruction valid through the pipeline stages. a flush will clear the valid signals
    logic D_valid, E_valid, M_valid, WB_valid;

    // PC signals
    logic [31:0] F_pcplus4, D_pcplus4, E_pcplus4;
    logic [31:0] E_PCTarget;
    logic E_chgPC, D_stall;

    // Decode and Register-file signals
    logic [4:0] D_rs, D_rt, D_rd, D_dest;
    logic [31:0] D_rdA, D_rdB, D_signimm;
    logic D_validRs, D_validRt, D_validRd, D_add, D_mul;
    logic E_stall, M_stall, WB_stall, D_hazard, D_mulStart, mulInFlight;

    // Execute signals and forwarding signals
    logic [31:0] E_operandA, E_operandB, E_signimm, E_mulProduct;
    logic [25:0] E_jumpidx;
    logic [4:0] E_rs, E_rt, E_dest;
    logic E_memtoreg, E_memwrite, E_branch;
    logic E_alusrc, E_regwrite, E_jump, E_add, E_mul;
    logic E_mulSecondCycle;
    logic [2:0] E_alucontrol;

    logic [31:0] E_forwardedA, E_forwardedB, E_srcB;
    logic [31:0] E_aluInputA, E_aluInputB;
    logic [2:0] E_aluInputControl;
    logic [31:0] E_aluResult, E_branchTarget, E_jumpTarget;
    logic E_zero;

    // Memory signals
    logic [31:0] M_aluResult, M_storeData, M_multResult;
    logic [4:0] M_dest;
    logic M_memtoreg, M_memwrite, M_regwrite;

    // Writeback signals
    logic [31:0] WB_aluResult, WB_readData, WB_result;
    logic [4:0] WB_dest;
    logic WB_memtoreg, WB_regwrite, WB_writeEnable;

    // Performance monitor signals
    logic [31:0] cycle_count;
    logic        incr_instr_cnt;
    logic [31:0] instr_count;
    logic        D_perfcyc;
    logic        D_perfinstr;
    // ============================================================
    // 1. Fetch logic
    // ============================================================
    assign F_pcplus4 = pc + 32'd4;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'b0;
        else if (E_chgPC)
            pc <= E_PCTarget;
        else if (!D_stall)
            pc <= F_pcplus4;
    end
    
    // ============================================================
    // 2. Fetch-to-decode pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            D_valid   <= 1'b0;
            D_instr   <= 32'b0;
            D_pcplus4 <= 32'b0;
        end else if (E_chgPC) begin // If branch/jump, flush the instruction in Decode stage
            D_valid   <= 1'b0;
            D_instr   <= 32'b0;
            D_pcplus4 <= 32'b0;
        end else if (!D_stall) begin // Register next instruction and PC+4 if there is no stall
            D_valid   <= 1'b1;
            D_instr   <= instr;
            D_pcplus4 <= F_pcplus4;
        end
    end

    // ============================================================
    // 3. Decode / register-file logic
    // ============================================================
    always_comb begin
        D_rs = D_instr[25:21]; // Operand A register number
        D_rt = D_instr[20:16]; // Operand B register number
        D_rd = D_instr[15:11]; // Destination register number for R-type instructions
        D_dest = D_regdst ? D_rd : D_rt;

        D_add = 1'b0;
        D_mul = 1'b0;
        D_perfcyc = 1'b0;
        D_perfinstr = 1'b0;

        case (opcode_t'(D_instr[31:26]))
            OP_RTYPE: begin
                case (funct_t'(D_instr[5:0]))
                    FUNCT_ADD: D_add = 1'b1;
                    FUNCT_MAC: D_mul = 1'b1;
                    default: ;
                endcase
            end
            OP_PERF: begin
                case (funct_t'(D_instr[5:0]))
                    FUNCT_PERF_CYC: D_perfcyc = 1'b1;
                    FUNCT_PERF_INST: D_perfinstr = 1'b1;
                    default: ;
                endcase
            end
            default: ;
        endcase

        if (D_perfcyc || D_perfinstr)
            D_signimm = 32'b0;
        else
            D_signimm = {{16{D_instr[15]}}, D_instr[15:0]};
    end

    regfile rf (
        .clk(clk),
        .we3(WB_writeEnable),
        .ra1(D_rs),
        // Reuse the second read port for rd during MULADD's add cycle.
        .ra2(E_mul ? D_rd : D_rt),
        .wa3(WB_dest),
        .wd3(WB_result),
        .rd1(D_rdA),
        .rd2(D_rdB)
    );

    perfmon perfmon ( .clk(clk), .reset(reset), 
                      .cycle_cnt(cycle_count), 
                      .incr_instr_cnt(incr_instr_cnt), 
                      .instr_cnt(instr_count) );

    // validate the source registers for the instruction in Decode stage. 
    // If the instruction is a MULADD, then the destination register is also a source register for the add cycle.
    always_comb begin
        D_validRs = 1'b0;
        D_validRt = 1'b0;
        D_validRd = 1'b0;

        if (D_valid && D_instr != 32'b0) begin
            case (opcode_t'(D_instr[31:26]))
                OP_RTYPE,
                OP_SW,
                OP_BEQ: begin
                    D_validRs = 1'b1;
                    D_validRt = 1'b1;
                end

                OP_LW,
                OP_ADDI: D_validRs = 1'b1;

                default: begin
                    D_validRs = 1'b0;
                    D_validRt = 1'b0;
                end
            endcase

            D_validRd = D_mul;
        end
    end
    
    // Function to check if Decode needs a register that an older instruction will write.
    function automatic logic D_reads_register(
        input logic [2:0] valid,
        input logic [4:0] src [2:0],
        input logic [4:0] register_number
    );
        D_reads_register =
            (valid[0] && src[0] == register_number) ||
            (valid[1] && src[1] == register_number) ||
            (valid[2] && src[2] == register_number);
    endfunction

    // Does Decode need a register an older instruction will write?
    assign E_stall = E_valid && E_regwrite && (E_dest != 5'd0) &&
                     D_reads_register({D_validRd,D_validRt,D_validRs},
                                      {D_rd, D_rt, D_rs}, E_dest);
    assign M_stall = M_valid && M_regwrite && (M_dest != 5'd0) &&
                     D_reads_register({D_validRd,D_validRt,D_validRs},
                                      {D_rd, D_rt, D_rs}, M_dest);
    assign WB_stall = WB_valid && WB_regwrite && (WB_dest != 5'd0) &&
                      D_reads_register({D_validRd,D_validRt,D_validRs},
                                       {D_rd, D_rt, D_rs}, WB_dest);

    // ADD can use forwarding except immediately after a load.
    // A W-stage dependency also stalls because RF writes occur
    // at the same rising edge as Decode operand capture.
    // The Decode copy of MULADD stays in place for both Execute cycles.
    // Ignore its own destination dependency while that copy is in Execute.
    assign mulInFlight = D_valid && E_valid && D_mul && E_mul;
    always_comb begin
        D_hazard = 1'b0;
        if (D_valid && !mulInFlight) begin // First cycle of MULADD is not a hazard to itself
            if (D_add) D_hazard = (E_stall && E_memtoreg) || WB_stall;
            else       D_hazard = E_stall || M_stall || WB_stall;
        end
    end
    assign D_mulStart = D_valid && D_mul && !mulInFlight && !D_hazard;
    // Hold Fetch/Decode during MULADD's multiply cycle. The stall releases
    // for its add cycle so the next instruction and PC advance on retirement.
    assign D_stall = D_hazard || D_mulStart ||
                     (E_valid && E_mul && !E_mulSecondCycle);

    // ============================================================
    // 4. Decode-to-execute pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            E_valid     <= 1'b0;
            E_operandA  <= 32'b0;
            E_operandB  <= 32'b0;
            E_signimm   <= 32'b0;
            E_pcplus4   <= 32'b0;
            E_jumpidx <= 26'b0;
            E_rs        <= 5'b0;
            E_rt        <= 5'b0;
            E_dest      <= 5'b0;
            E_memtoreg  <= 1'b0;
            E_memwrite  <= 1'b0;
            E_branch    <= 1'b0;
            E_alusrc    <= 1'b0;
            E_regwrite  <= 1'b0;
            E_jump      <= 1'b0;
            E_add     <= 1'b0;
            E_mul     <= 1'b0;
            E_mulSecondCycle <= 1'b0;
            E_mulProduct <= 32'b0;
            E_alucontrol <= 3'b010;
        end else if (E_valid && E_mul && !E_mulSecondCycle) begin
            // Cycle 1: latch rs * rt; keep the instruction and Decode copy.
            E_mulProduct <= E_aluResult;
            E_mulSecondCycle <= 1'b1;
        end else if (E_valid && E_mul && E_mulSecondCycle) begin
            // Cycle 2 has completed; retire MULADD and let Decode advance.
            E_valid    <= 1'b0;
            E_regwrite <= 1'b0;
            E_memwrite <= 1'b0;
            E_branch   <= 1'b0;
            E_jump     <= 1'b0;
            E_add    <= 1'b0;
            E_mul    <= 1'b0;
            E_mulSecondCycle <= 1'b0;
        end else if (E_chgPC || (D_stall && !D_mulStart)) begin
            // Bubble: no architectural side effects.
            E_valid    <= 1'b0;
            E_regwrite <= 1'b0;
            E_memwrite <= 1'b0;
            E_branch   <= 1'b0;
            E_jump     <= 1'b0;
            E_add    <= 1'b0;
            E_mul    <= 1'b0;
            E_mulSecondCycle <= 1'b0;
        end else begin
            // Treat an all-zero instruction as a NOP.
            E_valid     <= D_valid && (D_instr != 32'b0);
            E_operandA  <= D_perfcyc ? cycle_count : (D_perfinstr ? instr_count : D_rdA);
            E_operandB  <= D_rdB;
            E_signimm   <= D_signimm;
            E_pcplus4   <= D_pcplus4;
            E_jumpidx <= D_instr[25:0];
            E_rs        <= D_rs;
            E_rt        <= D_rt;
            E_dest      <= D_dest;
            E_memtoreg  <= D_memtoreg;
            E_memwrite  <= D_memwrite;
            E_branch    <= D_branch;
            E_alusrc    <= D_alusrc;
            E_regwrite  <= D_regwrite;
            E_jump      <= D_jump;
            E_add     <= D_add;
            E_mul     <= D_mul;
            E_mulSecondCycle <= 1'b0;
            E_alucontrol <= D_alucontrol;
        end
    end

    // ============================================================
    // 5. Execute logic
    // ============================================================

    // Forward operands directly, preferring the newer Memory-stage value.
    always_comb begin
        E_forwardedA = E_operandA;
        E_forwardedB = E_operandB;

        if (E_valid && E_add) begin
            if (M_valid && M_regwrite && !M_memtoreg &&
                M_dest != 5'd0 && M_dest == E_rs)
                E_forwardedA = M_aluResult;
            else if (WB_writeEnable && WB_dest != 5'd0 && WB_dest == E_rs)
                E_forwardedA = WB_result;

            if (M_valid && M_regwrite && !M_memtoreg &&
                M_dest != 5'd0 && M_dest == E_rt)
                E_forwardedB = M_aluResult;
            else if (WB_writeEnable && WB_dest != 5'd0 && WB_dest == E_rt)
                E_forwardedB = WB_result;
        end
    end

    assign E_srcB = E_alusrc ? E_signimm : E_forwardedB;

    assign E_aluInputA = (E_mul && E_mulSecondCycle)
                       ? E_mulProduct : E_forwardedA;
    assign E_aluInputB = (E_mul && E_mulSecondCycle)
                       ? D_rdB : E_srcB;
    assign E_aluInputControl = (E_mul && E_mulSecondCycle)
                             ? 3'b010 : E_alucontrol;

    alu alu (
        .a(E_aluInputA),
        .b(E_aluInputB),
        .control(E_aluInputControl),
        .result(E_aluResult),
        .zero(E_zero)
    );

    assign E_branchTarget = E_pcplus4 + (E_signimm << 2);
    assign E_jumpTarget = {E_pcplus4[31:28], E_jumpidx, 2'b00};

    // Branch or jump? If so, flush the instruction in Decode stage.
    assign E_chgPC = E_valid &&
                        (E_jump || (E_branch && E_zero));

    assign E_PCTarget = E_jump ? E_jumpTarget : E_branchTarget;

    // ============================================================
    // 6. Execute-to-memory pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            M_valid     <= 1'b0;
            M_aluResult <= 32'b0;
            M_storeData <= 32'b0;
            M_dest      <= 5'b0;
            M_memtoreg  <= 1'b0;
            M_memwrite  <= 1'b0;
            M_regwrite  <= 1'b0;
        end else begin
            // A MULADD only advances after its add cycle, never after multiply.
            M_valid     <= E_valid && (!E_mul || E_mulSecondCycle);
            M_aluResult <= E_aluResult;
            M_storeData <= E_forwardedB;
            M_dest      <= E_dest;
            M_memtoreg  <= E_valid && (!E_mul || E_mulSecondCycle) && E_memtoreg;
            M_memwrite  <= E_valid && (!E_mul || E_mulSecondCycle) && E_memwrite;
            M_regwrite  <= E_valid && (!E_mul || E_mulSecondCycle) && E_regwrite;
        end
    end
    // increment the instruction count for performance monitoring after the instructions have crossed the Memory stage.
    // so that we dont consider flushed instructions in the count
    assign incr_instr_cnt = M_valid || (D_instr == 32'b0);
    // ============================================================
    // 7. Memory logic
    // ============================================================
    assign aluout   = M_aluResult;
    assign writedata = M_storeData;
    assign memwrite = M_valid && M_memwrite;

    // ============================================================
    // 8. Memory-to-writeback pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            WB_valid     <= 1'b0;
            WB_aluResult <= 32'b0;
            WB_readData  <= 32'b0;
            WB_dest      <= 5'b0;
            WB_memtoreg  <= 1'b0;
            WB_regwrite  <= 1'b0;
        end else begin
            WB_valid     <= M_valid;
            WB_aluResult <= M_aluResult;
            WB_readData  <= readdata;
            WB_dest      <= M_dest;
            WB_memtoreg  <= M_memtoreg;
            WB_regwrite  <= M_regwrite;
        end
    end

    // ============================================================
    // 9. Writeback logic
    // ============================================================
    assign WB_result = WB_memtoreg ? WB_readData : WB_aluResult;
    assign WB_writeEnable = WB_valid && WB_regwrite;

endmodule


module regfile (
    input  logic        clk, we3,
    input  logic [4:0]  ra1, ra2, wa3,
    input  logic [31:0] wd3,
    output logic [31:0] rd1, rd2
);

    logic [31:0] rf [31:0];

    always_ff @(posedge clk) begin
        if (we3 && wa3 != 5'd0)
            rf[wa3] <= wd3;
    end

    assign rd1 = (ra1 == 5'd0) ? 32'b0 : rf[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'b0 : rf[ra2];

endmodule


module alu (
    input  logic [31:0] a, b,
    input  logic [2:0]  control,
    output logic [31:0] result,
    output logic        zero
);

    always_comb begin
        case (control)
            3'b000: result = a & b;
            3'b001: result = a | b;
            3'b010: result = a + b;
            3'b101: result = a * b;
            3'b110: result = a - b;
            3'b111: result = {31'b0, ($signed(a) < $signed(b))};
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);

endmodule


// ============================================================
// Performance monitor: counts cycles and reports on exit
// ============================================================
module perfmon (
    input  logic clk, reset,
    input  logic incr_instr_cnt,
    output logic [31:0] instr_cnt,
    output logic [31:0] cycle_cnt
);
    // Count cycles and instructions retired.
    always_ff @(posedge clk or posedge reset) begin
        if (reset) cycle_cnt <= 32'b0;
        else       cycle_cnt <= cycle_cnt + 1;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset)               instr_cnt <= 32'b0;
        else if (incr_instr_cnt) instr_cnt <= instr_cnt + 1;
    end
endmodule