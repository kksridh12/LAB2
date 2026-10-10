///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Testbench template for MIPS processor
// - This testbench uses two arrays (expected_data and expectd_addr) to store data and addresses of expected operations
// - and for each memory write, it checks if the memory writes match the expected values

// - Checks the MULADD program and its expected data-memory write.
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

timeunit 1ns;
timeprecision 1ps;

module MIPS_Testbench;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic [31:0] writedata, dataadr;
    logic memwrite;

    localparam int N = 2;
    localparam int MAX_CYCLES = 30;

    logic [31:0] expected_data [1:N];
    logic [31:0] expected_addr [1:N];

    int write_count = 0;
    int cycle_count = 0;
    int expected_instr_count = 0;
    int expected_cycle_count = 0;
    int check_perf_mon = 0;

    top dut (
        .clk(clk),
        .reset(reset),
        .writedata(writedata),
        .dataadr(dataadr),
        .memwrite(memwrite)
    );

    // Clock period: 10 ns
    always #5 clk = ~clk;

    // Expected store value from the current memfile.dat program.
    initial begin
        // Program sequence in memfile.dat:
        //   addi $1,$0,5
        //   addi $2,$0,3
        //   addi $4,$0,11
        //   muladd $4,$1,$2     // $4 = ($1 * $2) + $4 = 26
        //   sw   $4,0($0)
        expected_data[1] = 32'd26;
        expected_addr[1] = 32'd0;
        expected_data[2] = 32'd22;
        expected_addr[2] = 32'd4;
        expected_instr_count = 32'd9; // Total number of instructions executed in the program
        // Load the current instruction image while reset is still asserted.
        #1;
        $readmemh("memfile.dat", dut.imem.RAM);

        // Release reset away from the rising clock edge.
        repeat (2) @(negedge clk);
        reset = 1'b0;
    end

    // Record waveforms
    initial begin
        $dumpfile("pipeline.vcd");
        $dumpvars(0, MIPS_Testbench);
    end

    // Check stores at the same edge used by data memory.
    always @(posedge clk) begin
        if (!reset) begin
            cycle_count = cycle_count + 1;

            if (memwrite === 1'b1) begin
                write_count = write_count + 1;

                if (write_count > N)
                    $fatal(1, "Unexpected additional memory write");

                if (dataadr !== expected_addr[write_count] ||
                    writedata !== expected_data[write_count]) begin
                    $fatal(1,
                        "Write %0d FAILED: data=%h addr=%h; expected data=%h addr=%h",
                        write_count,
                        writedata,
                        dataadr,
                        expected_data[write_count],
                        expected_addr[write_count]
                    );
                end

                $display(
                    "Write %0d PASS: data=%h addr=%h cycle=%0d",
                    write_count, writedata, dataadr, cycle_count
                );

                if (write_count == N) begin
                    // Allow the final memory write to settle.
                    #1;
                    $display(
                        "TEST PASS: all %0d expected writes in %0d cycles",
                        N, cycle_count
                    );
                end
            end else if (memwrite !== 1'b0) begin
                $fatal(1, "memwrite is unknown");
            end
            if (cycle_count >= MAX_CYCLES)
                $fatal(1,
                    "TIMEOUT: only %0d/%0d writes observed",
                    write_count, N
                );
        end
    end

    always @(posedge dut.mips.dp.isPerfCycD) begin
        expected_cycle_count = cycle_count;
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        if (expected_cycle_count != dut.mips.dp.rf.rf[12])
            $fatal(1, "Cycle count mismatch: expected %0d, got %0d",
                expected_cycle_count, dut.mips.dp.rf.rf[12]);
        else
            $display("Expected Cycle Count: %0d, Actual Cycle Count: %0d", expected_cycle_count, dut.mips.dp.rf.rf[12]);
        check_perf_mon = check_perf_mon + 1;
    end
    always @(posedge dut.mips.dp.isPerfInstD) begin
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        @(posedge clk); // wait for instruction to execute
        if (expected_instr_count != dut.mips.dp.rf.rf[12])
            $fatal(1, "Instruction count mismatch: expected %0d, got %0d",
                expected_instr_count, dut.mips.dp.rf.rf[12]);
        else
            $display("Expected Instruction Count: %0d, Actual Instruction Count: %0d", expected_instr_count, dut.mips.dp.rf.rf[12]);
        check_perf_mon = check_perf_mon + 1;
    end

    always @(posedge clk) begin
        if (check_perf_mon == 2) begin
            $display("TEST PASS: Performance monitor counts are correct");
            $finish;
        end else if (cycle_count >= MAX_CYCLES) begin
            $fatal(1, "TIMEOUT: Performance monitor counts are incorrect");
        end
    end
    initial begin
				$fsdbDumpfile("novas.fsdb");
				$fsdbDumpvars(0, "+mda");
    end

endmodule