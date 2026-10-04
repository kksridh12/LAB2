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
    input  logic        memtoregD, memwriteD, branchD,
    input  logic        alusrcD, regdstD, regwriteD, jumpD,
    input  logic [2:0]  alucontrolD,

    // Instruction memory interface
    output logic [31:0] pc,
    input  logic [31:0] instr,
    output logic [31:0] instrD,

    // Data memory interface
    output logic        memwrite,
    output logic [31:0] aluout, writedata,
    input  logic [31:0] readdata
);

    logic validD, validE, validM, validW;

    logic [31:0] pcplus4F, pcplus4D, pcplus4E;
    logic [31:0] redirectTargetE;
    logic redirectE, stallD;

    logic [4:0] rsD, rtD, rdD, destD;
    logic [31:0] rd1D, rd2D, signimmD;
    logic usesRsD, usesRtD, isAddD;
    logic depE, depM, depW;

    logic [31:0] operandAE, operandBE, signimmE;
    logic [25:0] jumpIndexE;
    logic [4:0] rsE, rtE, destE;
    logic memtoregE, memwriteE, branchE;
    logic alusrcE, regwriteE, jumpE, isAddE;
    logic [2:0] alucontrolE;

    logic [31:0] forwardedAE, forwardedBE, srcBE;
    logic [31:0] aluResultE, branchTargetE, jumpTargetE;
    logic zeroE;
    logic [1:0] forwardAE, forwardBE;

    logic [31:0] aluResultM, storeDataM;
    logic [4:0] destM;
    logic memtoregM, memwriteM, regwriteM;

    logic [31:0] aluResultW, readDataW, resultW;
    logic [4:0] destW;
    logic memtoregW, regwriteW, writeEnableW;

    // ============================================================
    // 1. Fetch logic
    // ============================================================
    assign pcplus4F = pc + 32'd4;

    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'b0;
        else if (redirectE)
            pc <= redirectTargetE;
        else if (!stallD)
            pc <= pcplus4F;
    end

    // ============================================================
    // 2. Fetch-to-decode pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            validD   <= 1'b0;
            instrD   <= 32'b0;
            pcplus4D <= 32'b0;
        end else if (redirectE) begin
            validD   <= 1'b0;
            instrD   <= 32'b0;
            pcplus4D <= 32'b0;
        end else if (!stallD) begin
            validD   <= 1'b1;
            instrD   <= instr;
            pcplus4D <= pcplus4F;
        end
    end

    // ============================================================
    // 3. Decode / register-file logic
    // ============================================================
    assign rsD = instrD[25:21];
    assign rtD = instrD[20:16];
    assign rdD = instrD[15:11];

    assign destD = regdstD ? rdD : rtD;
    assign signimmD = {{16{instrD[15]}}, instrD[15:0]};

    assign isAddD = (instrD[31:26] == 6'b000000) &&
                    (instrD[5:0]   == 6'b100000);

    regfile rf (
        .clk(clk),
        .we3(writeEnableW),
        .ra1(rsD),
        .ra2(rtD),
        .wa3(destW),
        .wd3(resultW),
        .rd1(rd1D),
        .rd2(rd2D)
    );

    // Identify actual source registers.
    // J has no register operands; LW/ADDI use only rs.
    always_comb begin
        usesRsD = 1'b0;
        usesRtD = 1'b0;

        if (validD && instrD != 32'b0) begin
            case (instrD[31:26])
                6'b000000,
                6'b101011,
                6'b000100: begin
                    usesRsD = 1'b1;
                    usesRtD = 1'b1;
                end

                6'b100011,
                6'b001000: usesRsD = 1'b1;

                default: begin
                    usesRsD = 1'b0;
                    usesRtD = 1'b0;
                end
            endcase
        end
    end

    // Does Decode need a register an older instruction will write?
    assign depE = validE && regwriteE && (destE != 5'd0) &&
                  ((usesRsD && rsD == destE) ||
                   (usesRtD && rtD == destE));

    assign depM = validM && regwriteM && (destM != 5'd0) &&
                  ((usesRsD && rsD == destM) ||
                   (usesRtD && rtD == destM));

    assign depW = validW && regwriteW && (destW != 5'd0) &&
                  ((usesRsD && rsD == destW) ||
                   (usesRtD && rtD == destW));

    // ADD can use forwarding except immediately after a load.
    // A W-stage dependency also stalls because RF writes occur
    // at the same rising edge as Decode operand capture.
    assign stallD = validD &&
                    (isAddD
                        ? ((depE && memtoregE) || depW)
                        : (depE || depM || depW));

    // ============================================================
    // 4. Decode-to-execute pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            validE     <= 1'b0;
            operandAE  <= 32'b0;
            operandBE  <= 32'b0;
            signimmE   <= 32'b0;
            pcplus4E   <= 32'b0;
            jumpIndexE <= 26'b0;
            rsE        <= 5'b0;
            rtE        <= 5'b0;
            destE      <= 5'b0;
            memtoregE  <= 1'b0;
            memwriteE  <= 1'b0;
            branchE    <= 1'b0;
            alusrcE    <= 1'b0;
            regwriteE  <= 1'b0;
            jumpE      <= 1'b0;
            isAddE     <= 1'b0;
            alucontrolE <= 3'b010;
        end else if (redirectE || stallD) begin
            // Bubble: no architectural side effects.
            validE    <= 1'b0;
            regwriteE <= 1'b0;
            memwriteE <= 1'b0;
            branchE   <= 1'b0;
            jumpE     <= 1'b0;
            isAddE    <= 1'b0;
        end else begin
            // Treat an all-zero instruction as a NOP.
            validE     <= validD && (instrD != 32'b0);
            operandAE  <= rd1D;
            operandBE  <= rd2D;
            signimmE   <= signimmD;
            pcplus4E   <= pcplus4D;
            jumpIndexE <= instrD[25:0];
            rsE        <= rsD;
            rtE        <= rtD;
            destE      <= destD;
            memtoregE  <= memtoregD;
            memwriteE  <= memwriteD;
            branchE    <= branchD;
            alusrcE    <= alusrcD;
            regwriteE  <= regwriteD;
            jumpE      <= jumpD;
            isAddE     <= isAddD;
            alucontrolE <= alucontrolD;
        end
    end

    // ============================================================
    // 5. Execute logic
    // ============================================================

    // Forwarding selection:
    // 00 = captured register operand
    // 10 = Memory-stage ALU result
    // 01 = Writeback-stage result
    // Memory has priority because it is the newer producer.
    always_comb begin
        forwardAE = 2'b00;
        forwardBE = 2'b00;

        if (validE && isAddE) begin
            if (validM && regwriteM && !memtoregM &&
                destM != 5'd0 && destM == rsE)
                forwardAE = 2'b10;
            else if (writeEnableW &&
                     destW != 5'd0 && destW == rsE)
                forwardAE = 2'b01;

            if (validM && regwriteM && !memtoregM &&
                destM != 5'd0 && destM == rtE)
                forwardBE = 2'b10;
            else if (writeEnableW &&
                     destW != 5'd0 && destW == rtE)
                forwardBE = 2'b01;
        end

        case (forwardAE)
            2'b10:   forwardedAE = aluResultM;
            2'b01:   forwardedAE = resultW;
            default: forwardedAE = operandAE;
        endcase

        case (forwardBE)
            2'b10:   forwardedBE = aluResultM;
            2'b01:   forwardedBE = resultW;
            default: forwardedBE = operandBE;
        endcase
    end

    assign srcBE = alusrcE ? signimmE : forwardedBE;

    alu alu (
        .a(forwardedAE),
        .b(srcBE),
        .control(alucontrolE),
        .result(aluResultE),
        .zero(zeroE)
    );

    assign branchTargetE = pcplus4E + (signimmE << 2);
    assign jumpTargetE = {pcplus4E[31:28], jumpIndexE, 2'b00};

    assign redirectE = validE &&
                       (jumpE || (branchE && zeroE));

    assign redirectTargetE = jumpE ? jumpTargetE : branchTargetE;

    // ============================================================
    // 6. Execute-to-memory pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            validM     <= 1'b0;
            aluResultM <= 32'b0;
            storeDataM <= 32'b0;
            destM      <= 5'b0;
            memtoregM  <= 1'b0;
            memwriteM  <= 1'b0;
            regwriteM  <= 1'b0;
        end else begin
            validM     <= validE;
            aluResultM <= aluResultE;
            storeDataM <= forwardedBE;
            destM      <= destE;
            memtoregM  <= memtoregE;
            memwriteM  <= memwriteE;
            regwriteM  <= regwriteE;
        end
    end

    // ============================================================
    // 7. Memory logic
    // ============================================================
    assign aluout   = aluResultM;
    assign writedata = storeDataM;
    assign memwrite = validM && memwriteM && !reset;

    // ============================================================
    // 8. Memory-to-writeback pipeline registers
    // ============================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            validW     <= 1'b0;
            aluResultW <= 32'b0;
            readDataW  <= 32'b0;
            destW      <= 5'b0;
            memtoregW  <= 1'b0;
            regwriteW  <= 1'b0;
        end else begin
            validW     <= validM;
            aluResultW <= aluResultM;
            readDataW  <= readdata;
            destW      <= destM;
            memtoregW  <= memtoregM;
            regwriteW  <= regwriteM;
        end
    end

    // ============================================================
    // 9. Writeback logic
    // ============================================================
    assign resultW = memtoregW ? readDataW : aluResultW;
    assign writeEnableW = validW && regwriteW && !reset;

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
            3'b110: result = a - b;
            3'b111: result = {31'b0, ($signed(a) < $signed(b))};
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);

endmodule