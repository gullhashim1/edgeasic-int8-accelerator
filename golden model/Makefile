# EdgeASIC INT8 Accelerator -- simulation and golden-model flow
#
#   make            run every testbench
#   make golden     regenerate vectors + run the golden regression
#   make sweep      multi-seed random regression
#   make model      run golden-model self-tests only
#   make clean

IVERILOG := iverilog -g2012
VVP      := vvp
SIM      := sim
PY       := python3

PKG  := rtl/pkg/config_pkg.sv rtl/pkg/types_pkg.sv
CORE := rtl/core/pe_mac.sv rtl/core/systolic_array_8x8.sv rtl/core/sddu.sv \
        rtl/core/accum_buffer.sv rtl/core/accum_engine.sv

VEC_SEEDS ?= 1 7 42 1337 99999
VEC_BEATS ?= 5000

.PHONY: all pe array sddu accum adversarial golden sweep model clean dirs

all: pe array sddu accum adversarial golden

dirs:
	@mkdir -p $(SIM)

pe: dirs
	@echo "=== PE MAC ==="
	@$(IVERILOG) -o $(SIM)/pe.vvp $(PKG) rtl/core/pe_mac.sv tb/tb_pe_mac.sv
	@$(VVP) $(SIM)/pe.vvp

array: dirs
	@echo "=== 8x8 SYSTOLIC ARRAY ==="
	@$(IVERILOG) -o $(SIM)/array.vvp $(PKG) rtl/core/pe_mac.sv \
		rtl/core/systolic_array_8x8.sv tb/tb_systolic_array_8x8.sv
	@$(VVP) $(SIM)/array.vvp

sddu: dirs
	@echo "=== SDDU ==="
	@$(IVERILOG) -o $(SIM)/sddu.vvp $(PKG) rtl/core/sddu.sv tb/tb_SDDU.sv
	@$(VVP) $(SIM)/sddu.vvp

accum: dirs
	@echo "=== ACCUMULATOR (directed) ==="
	@$(IVERILOG) -o $(SIM)/accum.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv tb/tb_accum_system.sv
	@$(VVP) $(SIM)/accum.vvp

adversarial: dirs
	@echo "=== ACCUMULATOR (adversarial: stall + bypass + overflow) ==="
	@$(IVERILOG) -o $(SIM)/adv.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv tb/tb_accum_adversarial.sv
	@$(VVP) $(SIM)/adv.vvp

model:
	@echo "=== GOLDEN MODEL SELF-TESTS ==="
	@cd model && $(PY) test_model.py

vectors:
	@cd model && $(PY) gen_vectors.py --beats $(VEC_BEATS)

golden: dirs model vectors
	@echo "=== GOLDEN MODEL REGRESSION ==="
	@$(IVERILOG) -o $(SIM)/golden.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv tb/tb_accum_golden.sv
	@$(VVP) $(SIM)/golden.vvp

# Multi-seed sweep. Fails loudly if any seed mismatches.
sweep: dirs
	@$(IVERILOG) -o $(SIM)/golden.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv tb/tb_accum_golden.sv
	@fail=0; \
	for s in $(VEC_SEEDS); do \
		(cd model && $(PY) gen_vectors.py --beats $(VEC_BEATS) --seed $$s >/dev/null); \
		r=$$($(VVP) $(SIM)/golden.vvp 2>/dev/null | grep RESULT | sed 's/.*: //'); \
		echo "  seed $$s: $$r"; \
		case "$$r" in PASS*) ;; *) fail=1 ;; esac; \
	done; \
	if [ $$fail -ne 0 ]; then echo "SWEEP FAILED"; exit 1; fi; \
	echo "SWEEP PASSED"

clean:
	@rm -rf $(SIM) tb/vectors model/__pycache__
	@echo "cleaned"
