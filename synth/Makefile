all: synth clean_synth

# This runs synthesis with Design Compiler
synth_orig:
	dc_shell-t  -f  compile_orig_dc.tcl |& tee synth_orig.log
synth_orig_sr:
	dc_shell-t  -f  compile_orig_with_sram.tcl |& tee synth_orig_sr.log

synth_pipe:
	dc_shell-t  -f  compile_pipe_dc.tcl |& tee synth_pipe.log
synth_pipe_sr:
	dc_shell-t  -f  compile_pipe_with_sram.tcl |& tee synth_pipe_sr.log

clean_synth:
	\rm -rf *.syn *.pvl *.mr *.svf command.log  WORK

clean:
	\rm -rf csrc DVEFiles simv.daidir simv ucli.key vcdplus.vpd *.syn *.pvl *.mr *.svf command.log *.txt cksum_dir *.log *.rep WORK/

