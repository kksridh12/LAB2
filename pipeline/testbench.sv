///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Testbench template for MIPS processor
// - This testbench uses two arrays (expected_data and expectd_addr) to store data and addresses of expected operations
// - and for each memory write, it checks if the memory writes match the expected values

// - You need to modify these arrays to match the instructions in memfile.dat file used to initialize imem
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

timeunit 1ns;
timeprecision 1ps;

module MIPS_Testbench;

    logic clk = 1'b0;
    logic reset = 1'b1;

    logic [31:0] writedata, dataadr;
    logic memwrite;

    localparam int N = 7;
    localparam int MAX_CYCLES = 500;

    logic [31:0] expected_data [1:N];
    logic [31:0] expected_addr [1:N];

    int write_count = 0;
    int cycle_count = 0;

    top dut (
        .clk(clk),
        .reset(reset),
        .writedata(writedata),
        .dataadr(dataadr),
        .memwrite(memwrite)
    );

    // Clock period: 10 ns
    always #5 clk = ~clk;

    // Expected stores and reset initialization
    initial begin
        // ADD: 10 + 3 = 13
        expected_data[1] = 32'd13;
        expected_addr[1] = 32'd0;

        // SUB: 10 - 3 = 7
        expected_data[2] = 32'd7;
        expected_addr[2] = 32'd4;

        // AND: 10 & 3 = 2
        expected_data[3] = 32'd2;
        expected_addr[3] = 32'd8;

        // OR: 10 | 3 = 11
        expected_data[4] = 32'd11;
        expected_addr[4] = 32'd12;

        // SLT: 3 < 10 = 1
        expected_data[5] = 32'd1;
        expected_addr[5] = 32'd16;

        // LW: reload the previously stored value 13
        expected_data[6] = 32'd13;
        expected_addr[6] = 32'd20;

        // BEQ: skip stores to addresses 24 and 28
        expected_data[7] = 32'd10;
        expected_addr[7] = 32'd32;

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
                    $finish;
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

    initial begin
				$fsdbDumpfile("novas.fsdb");
				$fsdbDumpvars(0, "+mda");
    end

endmodule