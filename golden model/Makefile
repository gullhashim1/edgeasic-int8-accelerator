# EdgeASIC INT8 Accelerator -- Top-Level Simulation and Golden-Model Makefile
#
#   make                run every unit testbench (Datapath, Control, Memory, Golden Regressions)
#   make core           run compute datapath testbenches (PE, Array, SDDU, Accum, Requant)
#   make control        run control layer testbenches (CSR, Descriptor, Dispatcher)
#   make memory         run memory layer testbenches (Bank State Controller, Packing FIFO)
#   make requant        run requant directed testbench
#   make requant-golden run requant 5000-beat golden regression
#   make golden         regenerate vectors + run all golden regressions
#   make sweep          multi-seed random regression
#   make model          run Python golden-model self-tests only
#   make clean

IVERILOG := iverilog -g2012
VVP      := vvp
SIM      := sim
PY       := python3

PKG  := rtl/pkg/config_pkg.sv rtl/pkg/types_pkg.sv

VEC_SEEDS ?= 1 7 42 1337 99999
VEC_BEATS ?= 5000

.PHONY: all core control memory pe array sddu accum adversarial requant requant-golden csr desc disp bsc fifo golden sweep model vectors clean dirs

all: pe array sddu accum adversarial requant requant-golden csr desc disp bsc fifo

core: pe array sddu accum adversarial requant requant-golden

control: csr desc disp

memory: bsc fifo

dirs:
	@mkdir -p $(SIM) tb/vectors

# ============================================================================
# Core Compute Datapath Targets (Weeks 5 - 8)
# ============================================================================

pe: dirs
	@echo "=== [1/10] PE MAC ==="
	@$(IVERILOG) -o $(SIM)/pe.vvp $(PKG) rtl/core/pe_mac.sv tb/tb_pe_mac.sv
	@$(VVP) $(SIM)/pe.vvp

array: dirs
	@echo "=== [2/10] 8x8 SYSTOLIC ARRAY ==="
	@$(IVERILOG) -o $(SIM)/array.vvp $(PKG) rtl/core/pe_mac.sv \
		rtl/core/systolic_array_8x8.sv tb/tb_systolic_array_8x8.sv
	@$(VVP) $(SIM)/array.vvp

sddu: dirs
	@echo "=== [3/10] SDDU (Basic Deskew) ==="
	@$(IVERILOG) -o $(SIM)/sddu.vvp $(PKG) rtl/core/sddu.sv tb/tb_SDDU.sv
	@$(VVP) $(SIM)/sddu.vvp
	@echo "=== [3/10] SDDU (Metadata & Data Integrity) ==="
	@$(IVERILOG) -o $(SIM)/sddu_meta.vvp $(PKG) rtl/core/sddu.sv tb/tb_sddu_meta.sv
	@$(VVP) $(SIM)/sddu_meta.vvp

accum: dirs
	@echo "=== [4/10] ACCUMULATOR (directed) ==="
	@$(IVERILOG) -o $(SIM)/accum.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv tb/tb_accum_system.sv
	@$(VVP) $(SIM)/accum.vvp

adversarial: dirs
	@echo "=== [5/10] ACCUMULATOR (adversarial: stall + bypass + overflow) ==="
	@$(IVERILOG) -o $(SIM)/adv.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv 'golden model/tb_accum_adversarial.sv'
	@$(VVP) $(SIM)/adv.vvp

requant: dirs
	@echo "=== [6/10] REQUANT (directed) ==="
	@$(IVERILOG) -o $(SIM)/requant.vvp $(PKG) rtl/core/requant.sv tb/tb_requant.sv
	@$(VVP) $(SIM)/requant.vvp

requant-golden: dirs vectors
	@echo "=== [6/10] REQUANT (golden 5000-beat regression) ==="
	@$(IVERILOG) -o $(SIM)/requant_golden.vvp $(PKG) rtl/core/requant.sv tb/tb_requant_golden.sv
	@$(VVP) $(SIM)/requant_golden.vvp

# ============================================================================
# Control Plane Targets (Week 3)
# ============================================================================

csr: dirs
	@echo "=== [7/10] CSR BLOCK (TC-CSR-001/002) ==="
	@$(IVERILOG) -o $(SIM)/csr.vvp $(PKG) rtl/control/csr_block.sv tb/tb_csr_block.sv
	@$(VVP) $(SIM)/csr.vvp

desc: dirs
	@echo "=== [8/10] DESCRIPTOR MANAGER (TC-DESC-001/002) ==="
	@$(IVERILOG) -o $(SIM)/desc.vvp $(PKG) rtl/control/descriptor_manager.sv tb/tb_descriptor_manager.sv
	@$(VVP) $(SIM)/desc.vvp

disp: dirs
	@echo "=== [9/10] OPERATOR DISPATCHER (TC-ERR-001) ==="
	@$(IVERILOG) -o $(SIM)/disp.vvp $(PKG) rtl/control/operator_dispatcher.sv tb/tb_operator_dispatcher.sv
	@$(VVP) $(SIM)/disp.vvp

# ============================================================================
# Memory Plane Targets (Weeks 4 & 9)
# ============================================================================

bsc: dirs
	@echo "=== [10/10] BANK STATE CONTROLLER (TC-BSC-001/002) ==="
	@$(IVERILOG) -o $(SIM)/bsc.vvp $(PKG) rtl/memory/bank_state_controller.sv tb/tb_bank_state_controller.sv
	@$(VVP) $(SIM)/bsc.vvp

fifo: dirs
	@echo "=== [10/10] PACKING FIFO (TC-FIFO-001/002) ==="
	@$(IVERILOG) -o $(SIM)/fifo.vvp $(PKG) rtl/memory/packing_fifo.sv tb/tb_packing_fifo.sv
	@$(VVP) $(SIM)/fifo.vvp

# ============================================================================
# Golden Model & Regression Targets
# ============================================================================

model:
	@echo "=== GOLDEN MODEL SELF-TESTS ==="
	@$(PY) 'golden model/test_model.py'

vectors: dirs
	@$(PY) 'golden model/gen_vectors.py' --target all --beats $(VEC_BEATS) --out tb/vectors

golden: dirs model vectors requant-golden
	@echo "=== ACCUMULATOR GOLDEN MODEL REGRESSION ==="
	@$(IVERILOG) -o $(SIM)/golden.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv 'golden model/tb_accum_golden.sv'
	@$(VVP) $(SIM)/golden.vvp

# Multi-seed sweep across both Accumulator and Requant
sweep: dirs
	@$(IVERILOG) -o $(SIM)/golden.vvp $(PKG) rtl/core/accum_buffer.sv \
		rtl/core/accum_engine.sv 'golden model/tb_accum_golden.sv'
	@$(IVERILOG) -o $(SIM)/req_gold.vvp $(PKG) rtl/core/requant.sv tb/tb_requant_golden.sv
	@fail=0; \
	for s in $(VEC_SEEDS); do \
		echo "--- Running seed $$s ---"; \
		$(PY) 'golden model/gen_vectors.py' --target all --beats $(VEC_BEATS) --seed $$s --out tb/vectors >/dev/null; \
		r_acc=$$($(VVP) $(SIM)/golden.vvp 2>/dev/null | grep RESULT | sed 's/.*: //'); \
		r_req=$$($(VVP) $(SIM)/req_gold.vvp 2>/dev/null | grep RESULT | sed 's/.*: //'); \
		echo "  [ACCUM]   seed $$s: $$r_acc"; \
		echo "  [REQUANT] seed $$s: $$r_req"; \
		case "$$r_acc" in PASS*) ;; *) fail=1 ;; esac; \
		case "$$r_req" in PASS*) ;; *) fail=1 ;; esac; \
	done; \
	if [ $$fail -ne 0 ]; then echo "SWEEP FAILED"; exit 1; fi; \
	echo "SWEEP PASSED (ALL SEEDS 100% BIT-EXACT)"

clean:
	@rm -rf $(SIM) tb/vectors 'golden model'/__pycache__
	@echo "cleaned"
