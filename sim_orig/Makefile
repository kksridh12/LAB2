VCS ?= $(VCS_HOME)/bin/vcs
VERDI ?= $(VERDI_HOME)/bin/verdi

SV_SRCS := \
	../original/testbench.v \
	../original/top.v \
	../original/controller.v \
	../original/datapath.v

all: compile_and_sim

# Compile and immediately run simulation
compile_and_sim:
	cp ../original/memfile.dat .
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
sim:
	cp ../original/memfile.dat .
	./simv

# Launch Verdi
verdi:
	$(VERDI) -dbdir ./simv.daidir -nologo

waves_verdi:
	$(VERDI) -dbdir ./simv.daidir -ssf novas.fsdb -nologo

clean:
	rm -rf *.log *.h csrc DVEFiles simv.daidir simv ucli.key \
	vcdplus.vpd *.syn *.pvl *.mr *.svf command.log *.txt \
	verdi_config_file verdiLog novas.fsdb novas.log
