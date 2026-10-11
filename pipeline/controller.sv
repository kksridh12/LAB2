module controller (
    input  opcode_t    op,
    input  funct_t     funct,
    output logic       D_memtoreg,
    output logic       D_memwrite,
    output logic       D_branch,
    output logic       D_alusrc,
    output logic       D_regdst,
    output logic       D_regwrite,
    output logic       D_jump,
    output logic [2:0] D_alucontrol
);

    logic [1:0] D_aluop;

    maindec md ( .* );

    aludec ad ( .* );


endmodule


module maindec (
    input  opcode_t op,
    output logic   D_memtoreg,
    output logic   D_memwrite,
    output logic   D_branch,
    output logic   D_alusrc,
    output logic   D_regdst,
    output logic   D_regwrite,
    output logic   D_jump,
    output logic [1:0] D_aluop
);

    logic [8:0] controls;

    assign {
        D_regwrite, D_regdst, D_alusrc, D_branch,
        D_memwrite, D_memtoreg, D_jump, D_aluop
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
    input  logic [1:0] D_aluop,
    output logic [2:0] D_alucontrol
);

    always_comb begin
        case (D_aluop)
            2'b00: D_alucontrol = 3'b010; // LW, SW, ADDI: add
            2'b01: D_alucontrol = 3'b110; // BEQ: subtract
            2'b10: begin
                case (funct)
                    FUNCT_ADD: D_alucontrol = 3'b010; // ADD
                    FUNCT_MAC: D_alucontrol = 3'b101; // MAC
                    FUNCT_SUB: D_alucontrol = 3'b110; // SUB
                    FUNCT_AND: D_alucontrol = 3'b000; // AND
                    FUNCT_OR:  D_alucontrol = 3'b001; // OR
                    FUNCT_SLT: D_alucontrol = 3'b111; // SLT
                    default:   D_alucontrol = 3'b010;
                endcase
            end
            default: D_alucontrol = 3'b010;
        endcase
    end

endmodule