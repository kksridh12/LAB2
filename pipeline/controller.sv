module controller (
    input  opcode_t op,
    input  funct_t  funct,
    output logic       memtoregD,
    output logic       memwriteD,
    output logic       branchD,
    output logic       alusrcD,
    output logic       regdstD,
    output logic       regwriteD,
    output logic       jumpD,
    output logic [2:0] alucontrolD
);

    logic [1:0] aluopD;

    maindec md (
        .op(op),
        .memtoreg(memtoregD),
        .memwrite(memwriteD),
        .branch(branchD),
        .alusrc(alusrcD),
        .regdst(regdstD),
        .regwrite(regwriteD),
        .jump(jumpD),
        .aluop(aluopD)
    );

    aludec ad (
        .funct(funct),
        .aluop(aluopD),
        .alucontrol(alucontrolD)
    );

endmodule


module maindec (
    input  opcode_t op,
    output logic   memtoreg,
    output logic   memwrite,
    output logic   branch,
    output logic   alusrc,
    output logic   regdst,
    output logic   regwrite,
    output logic   jump,
    output logic [1:0] aluop
);

    logic [8:0] controls;

    assign {
        regwrite, regdst, alusrc, branch,
        memwrite, memtoreg, jump, aluop
    } = controls;

    always_comb begin
        case (op)
            OP_RTYPE: controls = 9'b110000010; // R-type
            OP_LW:    controls = 9'b101001000; // LW
            OP_SW:    controls = 9'b001010000; // SW
            OP_BEQ:   controls = 9'b000100001; // BEQ
            OP_ADDI:  controls = 9'b101000000; // ADDI
            OP_J:     controls = 9'b000000100; // J
            OP_PERF:  controls = 9'b111000000; // PERF
            default:  controls = 9'b000000000;
        endcase
    end

endmodule


module aludec (
    input  funct_t  funct,
    input  logic [1:0] aluop,
    output logic [2:0] alucontrol
);

    always_comb begin
        case (aluop)
            2'b00: alucontrol = 3'b010; // LW, SW, ADDI: add
            2'b01: alucontrol = 3'b110; // BEQ: subtract
            2'b10: begin
                case (funct)
                    FUNCT_ADD: alucontrol = 3'b010; // ADD
                    FUNCT_MAC: alucontrol = 3'b101; // MAC
                    FUNCT_SUB: alucontrol = 3'b110; // SUB
                    FUNCT_AND: alucontrol = 3'b000; // AND
                    FUNCT_OR:  alucontrol = 3'b001; // OR
                    FUNCT_SLT: alucontrol = 3'b111; // SLT
                    default:   alucontrol = 3'b010;
                endcase
            end
            default: alucontrol = 3'b010;
        endcase
    end

endmodule