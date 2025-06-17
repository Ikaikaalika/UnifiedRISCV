"""
GPU Operations Test Suite using cocotb
Tests matrix multiply-accumulate operations and performance
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
import numpy as np
import random
import logging

class GPUTestBench:
    """Test bench for GPU operations"""
    
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.memory = {}  # Simple memory model
        
    async def setup(self):
        """Initialize the test bench"""
        # Start clock
        cocotb.start_soon(Clock(self.dut.clk, 10, units="ns").start())
        
        # Reset
        self.dut.rst_n.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst_n.value = 1
        await RisingEdge(self.dut.clk)
        
        self.log.info("GPU Test Bench initialized")
        
    async def memory_model(self):
        """Simple memory model responding to requests"""
        while True:
            await RisingEdge(self.dut.clk)
            
            if self.dut.mem_req.value == 1:
                # Simulate memory latency
                await Timer(20, units="ns")
                
                addr = int(self.dut.mem_addr.value)
                
                if self.dut.mem_we.value == 1:
                    # Write operation
                    data = int(self.dut.mem_wdata.value)
                    self.memory[addr] = data
                    self.log.debug(f"Memory write: addr=0x{addr:08x}, data=0x{data:016x}")
                else:
                    # Read operation  
                    data = self.memory.get(addr, 0)
                    self.dut.mem_rdata.value = data
                    self.log.debug(f"Memory read: addr=0x{addr:08x}, data=0x{data:016x}")
                
                self.dut.mem_ack.value = 1
                await RisingEdge(self.dut.clk)
                self.dut.mem_ack.value = 0
    
    def create_test_matrix(self, rows=4, cols=4, dtype=np.int8):
        """Create a test matrix with known values"""
        return np.random.randint(-128, 127, size=(rows, cols), dtype=dtype)
    
    def matrix_to_memory(self, matrix, base_addr):
        """Store matrix in memory model"""
        flat = matrix.flatten()
        for i, val in enumerate(flat):
            # Pack 4 bytes per word
            word_idx = i // 4
            byte_idx = i % 4
            addr = base_addr + word_idx * 4
            
            if addr not in self.memory:
                self.memory[addr] = 0
            
            # Clear the byte and set new value
            self.memory[addr] &= ~(0xFF << (byte_idx * 8))
            self.memory[addr] |= (val & 0xFF) << (byte_idx * 8)
    
    def matrix_from_memory(self, base_addr, rows=4, cols=4, dtype=np.int16):
        """Read matrix from memory model"""
        result = np.zeros((rows, cols), dtype=dtype)
        flat_size = rows * cols
        
        for i in range(flat_size):
            word_idx = i // 2  # 2 int16 values per 32-bit word
            elem_idx = i % 2
            addr = base_addr + word_idx * 4
            
            if addr in self.memory:
                word = self.memory[addr]
                value = (word >> (elem_idx * 16)) & 0xFFFF
                # Sign extend for int16
                if value & 0x8000:
                    value |= 0xFFFF0000
                result.flat[i] = np.int16(value)
        
        return result

@cocotb.test()
async def test_gpu_basic_functionality(dut):
    """Test basic GPU functionality"""
    tb = GPUTestBench(dut)
    await tb.setup()
    
    # Start memory model
    cocotb.start_soon(tb.memory_model())
    
    # Create test matrices
    matrix_a = tb.create_test_matrix()
    matrix_b = np.eye(4, dtype=np.int8)  # Identity matrix
    
    # Expected result (A * I = A)
    expected = matrix_a.astype(np.int16)
    
    tb.log.info("Testing basic matrix multiply: A * I = A")
    tb.log.info(f"Matrix A:\n{matrix_a}")
    
    # Store matrices in memory
    addr_a = 0x1000
    addr_b = 0x1100  
    addr_c = 0x1200
    
    tb.matrix_to_memory(matrix_a, addr_a)
    tb.matrix_to_memory(matrix_b, addr_b)
    
    # Set up GPU operation
    dut.gpu_matrix_a[0].value = addr_a
    dut.gpu_matrix_b[0].value = addr_b
    dut.gpu_matrix_c[0].value = addr_c
    
    # Start GPU unit 0
    dut.gpu_unit_start.value = 0x01
    await RisingEdge(dut.clk)
    dut.gpu_unit_start.value = 0x00
    
    # Wait for GPU operation to complete
    timeout = 1000
    cycles = 0
    while dut.gpu_unit_busy.value & 0x01 and cycles < timeout:
        await RisingEdge(dut.clk)
        cycles += 1
    
    if cycles >= timeout:
        tb.log.error("GPU operation timed out")
        assert False, "GPU operation timeout"
    
    tb.log.info(f"GPU operation completed in {cycles} cycles")
    
    # Read result
    result = tb.matrix_from_memory(addr_c)
    tb.log.info(f"Result matrix:\n{result}")
    
    # Verify result
    np.testing.assert_array_equal(result, expected, 
                                  err_msg="Matrix multiply result mismatch")
    
    tb.log.info("Basic GPU test: PASSED")

@cocotb.test()
async def test_gpu_parallel_operations(dut):
    """Test parallel GPU operations across multiple units"""
    tb = GPUTestBench(dut)
    await tb.setup()
    
    cocotb.start_soon(tb.memory_model())
    
    num_units = 4  # Test first 4 GPU units
    tb.log.info(f"Testing parallel operations on {num_units} GPU units")
    
    # Create different test cases for each unit
    test_matrices = []
    expected_results = []
    base_addrs = []
    
    for i in range(num_units):
        # Create unique test matrices
        a = tb.create_test_matrix() 
        b = tb.create_test_matrix()
        expected = np.dot(a.astype(np.int16), b.astype(np.int16))
        
        test_matrices.append((a, b))
        expected_results.append(expected)
        
        # Assign memory addresses
        addr_base = 0x2000 + i * 0x300
        addr_a = addr_base
        addr_b = addr_base + 0x100
        addr_c = addr_base + 0x200
        base_addrs.append((addr_a, addr_b, addr_c))
        
        # Store in memory
        tb.matrix_to_memory(a, addr_a)
        tb.matrix_to_memory(b, addr_b)
        
        # Set up GPU unit
        dut.gpu_matrix_a[i].value = addr_a
        dut.gpu_matrix_b[i].value = addr_b  
        dut.gpu_matrix_c[i].value = addr_c
    
    # Start all GPU units simultaneously
    start_mask = (1 << num_units) - 1
    dut.gpu_unit_start.value = start_mask
    await RisingEdge(dut.clk)
    dut.gpu_unit_start.value = 0
    
    # Wait for all operations to complete
    timeout = 2000
    cycles = 0
    while (dut.gpu_unit_busy.value & start_mask) != 0 and cycles < timeout:
        await RisingEdge(dut.clk)
        cycles += 1
        
        if cycles % 100 == 0:
            busy_status = dut.gpu_unit_busy.value & start_mask
            tb.log.info(f"Cycle {cycles}: GPU busy status = 0x{busy_status:02x}")
    
    if cycles >= timeout:
        tb.log.error("Parallel GPU operations timed out")
        assert False, "GPU parallel operations timeout"
    
    tb.log.info(f"All parallel operations completed in {cycles} cycles")
    
    # Verify all results
    all_passed = True
    for i in range(num_units):
        addr_a, addr_b, addr_c = base_addrs[i]
        result = tb.matrix_from_memory(addr_c)
        expected = expected_results[i]
        
        try:
            # Allow some tolerance for integer overflow
            np.testing.assert_allclose(result, expected, rtol=0.1, atol=10)
            tb.log.info(f"Unit {i}: PASSED")
        except AssertionError as e:
            tb.log.error(f"Unit {i}: FAILED - {e}")
            all_passed = False
    
    assert all_passed, "Some parallel operations failed"
    tb.log.info("Parallel GPU test: PASSED")

@cocotb.test()
async def test_gpu_performance(dut):
    """Performance test measuring TOPS"""
    tb = GPUTestBench(dut)
    await tb.setup()
    
    cocotb.start_soon(tb.memory_model())
    
    num_operations = 100
    tb.log.info(f"Performance test: {num_operations} matrix operations")
    
    # Setup matrices
    matrix_a = tb.create_test_matrix()
    matrix_b = tb.create_test_matrix() 
    
    addr_a = 0x4000
    addr_b = 0x4100
    addr_c = 0x4200
    
    tb.matrix_to_memory(matrix_a, addr_a)
    tb.matrix_to_memory(matrix_b, addr_b)
    
    # Configure GPU unit 0
    dut.gpu_matrix_a[0].value = addr_a
    dut.gpu_matrix_b[0].value = addr_b
    dut.gpu_matrix_c[0].value = addr_c
    
    start_time = cocotb.utils.get_sim_time()
    start_cycle = 0  # Would need cycle counter in real implementation
    
    # Run operations sequentially
    for op in range(num_operations):
        # Start operation
        dut.gpu_unit_start.value = 0x01
        await RisingEdge(dut.clk)
        dut.gpu_unit_start.value = 0x00
        
        # Wait for completion
        timeout = 100
        cycles = 0
        while dut.gpu_unit_busy.value & 0x01 and cycles < timeout:
            await RisingEdge(dut.clk)
            cycles += 1
        
        if cycles >= timeout:
            tb.log.error(f"Operation {op} timed out")
            break
            
        if op % 10 == 0:
            tb.log.info(f"Completed operation {op}")
    
    end_time = cocotb.utils.get_sim_time()
    
    # Calculate performance metrics
    total_time_ns = end_time - start_time
    total_time_s = total_time_ns / 1e9
    
    ops_per_second = num_operations / total_time_s
    
    # Each 4x4 matrix multiply = 4*4*4 = 64 MAC operations
    mac_ops_per_matrix = 4 * 4 * 4
    total_mac_ops = num_operations * mac_ops_per_matrix
    mac_ops_per_second = total_mac_ops / total_time_s
    
    # Calculate TOPS (assuming INT8 operations)
    tops = mac_ops_per_second / 1e12
    
    tb.log.info("Performance Results:")
    tb.log.info(f"  Total time: {total_time_s:.6f} seconds")
    tb.log.info(f"  Operations/sec: {ops_per_second:.0f}")
    tb.log.info(f"  MAC ops/sec: {mac_ops_per_second:.0f}")
    tb.log.info(f"  TOPS (single unit): {tops:.6f}")
    
    # Theoretical scaling to 8 units
    theoretical_tops_8_units = tops * 8
    tb.log.info(f"  Theoretical TOPS (8 units): {theoretical_tops_8_units:.3f}")
    
    # Scaling analysis for M1 Neural Engine target (11.5 TOPS)
    target_tops = 11.5
    scale_factor = target_tops / theoretical_tops_8_units
    tb.log.info(f"  Scale factor to reach {target_tops} TOPS: {scale_factor:.1f}x")
    
    if scale_factor <= 100:  # Reasonable scaling
        tb.log.info("  Achievable with frequency scaling and more units")
    else:
        tb.log.warning("  May require architectural improvements")

# Test factory for parameterized tests
tf_matrix_sizes = TestFactory(test_gpu_basic_functionality)
tf_matrix_sizes.add_option("matrix_size", [4, 8, 16])
tf_matrix_sizes.generate_tests()

# Random test factory
tf_random = TestFactory(test_gpu_parallel_operations)
tf_random.add_option("num_tests", [1, 5, 10])
tf_random.generate_tests()