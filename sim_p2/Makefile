VCS ?= $(VCS_HOME)/bin/vcs
VERDI ?= $(VERDI_HOME)/bin/verdi

SV_SRCS := \
	../pipeline/testbench_p2.sv \
	../pipeline/top.sv \
	../pipeline/controller.sv \
	../pipeline/datapath.sv

all: compile_and_sim

# Compile and immediately run simulation
compile_and_sim:
	cp -f ../pipeline/memfile_muladd.dat memfile.dat
	$(VCS) -R -full64 -sverilog $(SV_SRCS) \
	-kdb -lca -debug_access+all |& tee compile_and_sim.log

# Compile only
compile:
	$(VCS) -full64 -sverilog $(SV_SRCS) \
	-debug_access+all |& tee compile.log

# Compile with Verdi database support
compile_verdi:
	$(VCS) -full64 -sverilog $(SV_SRCS) \
	-debug_access+all -kdb -lca |& tee compile_verdi.log

# Run already-compiled simulation
sim_muladd:
	cp -f ../pipeline/memfile_muladd.dat memfile.dat 
	./simv

# Launch Verdi
verdi:
	$(VERDI) -dbdir ./simv.daidir -nologo

waves_verdi:
	$(VERDI) -dbdir ./simv.daidir -ssf novas.fsdb -nologo

clean:
	rm -rf *.log *.h csrc DVEFiles simv.daidir simv ucli.key \
	vcdplus.vpd *.syn *.pvl *.mr *.svf command.log *.conf *.txt \
	verdi_config_file verdiLog novas.fsdb novas.log *.vcd *.dat novas.rc
