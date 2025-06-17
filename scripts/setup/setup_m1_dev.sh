#!/bin/bash
# UnifiedRISCV Development Environment Setup for Apple Silicon (M1/M2)
# Installs all necessary tools and dependencies

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Apple Silicon
check_apple_silicon() {
    if [[ $(uname -m) != "arm64" ]]; then
        log_error "This script is designed for Apple Silicon Macs (M1/M2)"
        log_error "Detected architecture: $(uname -m)"
        exit 1
    fi
    log_success "Running on Apple Silicon ($(uname -m))"
}

# Check and install Homebrew
install_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        log_success "Homebrew already installed"
        brew update
    else
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        log_success "Homebrew installed successfully"
    fi
}

# Install development tools
install_dev_tools() {
    log_info "Installing development tools..."
    
    # Essential tools
    brew install git cmake ninja make
    
    # Verilator (HDL simulator)
    if ! command -v verilator >/dev/null 2>&1; then
        log_info "Installing Verilator..."
        brew install verilator
        log_success "Verilator installed"
    else
        log_success "Verilator already installed"
    fi
    
    # GTKWave (waveform viewer)
    if ! command -v gtkwave >/dev/null 2>&1; then
        log_info "Installing GTKWave..."
        brew install gtkwave
        log_success "GTKWave installed"
    else
        log_success "GTKWave already installed"
    fi
    
    # RISC-V toolchain
    if ! command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
        log_info "Installing RISC-V toolchain..."
        brew tap riscv-software-src/riscv
        brew install riscv-tools
        log_success "RISC-V toolchain installed"
    else
        log_success "RISC-V toolchain already installed"
    fi
}

# Install Python and packages
install_python_env() {
    log_info "Setting up Python environment..."
    
    # Install Python 3.9+ (optimized for M1)
    if ! command -v python3 >/dev/null 2>&1; then
        brew install python@3.11
    fi
    
    # Verify Python version
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
    log_info "Python version: $PYTHON_VERSION"
    
    # Install pip
    if ! command -v pip3 >/dev/null 2>&1; then
        log_info "Installing pip..."
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python3 get-pip.py
        rm get-pip.py
    fi
    
    # Create virtual environment
    if [[ ! -d "venv" ]]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv venv
    fi
    
    # Activate virtual environment and install packages
    source venv/bin/activate
    
    # Upgrade pip and install wheel
    pip install --upgrade pip wheel setuptools
    
    # Install M1-optimized packages
    log_info "Installing Python packages (this may take a while on first run)..."
    
    # Core packages
    pip install numpy scipy matplotlib seaborn pandas
    
    # HDL verification
    pip install cocotb cocotb-test pytest pytest-html
    
    # Machine Learning (M1 optimized)
    if [[ $PYTHON_VERSION == "3.11" || $PYTHON_VERSION == "3.10" || $PYTHON_VERSION == "3.9" ]]; then
        log_info "Installing PyTorch for Apple Silicon..."
        pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
        
        log_info "Installing TensorFlow for Apple Silicon..."
        pip install tensorflow-macos tensorflow-metal
    else
        log_warning "Python version $PYTHON_VERSION may not have optimized ML packages for M1"
        pip install torch torchvision
    fi
    
    # Development tools
    pip install jupyter black flake8 mypy
    
    deactivate
    log_success "Python environment setup complete"
}

# Install FPGA tools (optional)
install_fpga_tools() {
    read -p "Install FPGA development tools? (Vivado/Quartus are large downloads) [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "FPGA tools installation..."
        
        # Yosys (open source synthesis)
        if ! command -v yosys >/dev/null 2>&1; then
            log_info "Installing Yosys..."
            brew install yosys
        fi
        
        # NextPNR (open source place and route)
        if ! command -v nextpnr-ice40 >/dev/null 2>&1; then
            log_info "Installing NextPNR..."
            brew install nextpnr-ice40 nextpnr-ecp5
        fi
        
        log_info "For Xilinx Vivado or Intel Quartus, please download from vendor websites"
        log_info "Vivado: https://www.xilinx.com/support/download.html"
        log_info "Quartus: https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/download.html"
        
        log_success "Open source FPGA tools installed"
    else
        log_info "Skipping FPGA tools installation"
    fi
}

# Configure environment
configure_environment() {
    log_info "Configuring development environment..."
    
    # Create .env file for project
    cat > .env << EOF
# UnifiedRISCV Development Environment
export UNIFIED_RISCV_ROOT=$(pwd)
export RISCV_PREFIX=riscv32-unknown-elf-
export VERILATOR_ROOT=/opt/homebrew
export PATH=\$VERILATOR_ROOT/bin:\$PATH

# Python virtual environment
if [[ -d "\$UNIFIED_RISCV_ROOT/venv" ]]; then
    source \$UNIFIED_RISCV_ROOT/venv/bin/activate
fi

# M1 optimizations
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
EOF
    
    # Add to shell profile if not already there
    SHELL_RC=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        SHELL_RC="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        SHELL_RC="$HOME/.bashrc"
    fi
    
    if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
        if ! grep -q "UnifiedRISCV" "$SHELL_RC"; then
            echo "" >> "$SHELL_RC"
            echo "# UnifiedRISCV Development Environment" >> "$SHELL_RC"
            echo "if [[ -f \"\$PWD/.env\" ]]; then" >> "$SHELL_RC"
            echo "    source \"\$PWD/.env\"" >> "$SHELL_RC"
            echo "fi" >> "$SHELL_RC"
            log_success "Added environment setup to $SHELL_RC"
        fi
    fi
    
    log_success "Environment configuration complete"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check essential tools
    for tool in git cmake make verilator gtkwave python3; do
        if command -v $tool >/dev/null 2>&1; then
            local version=$($tool --version 2>/dev/null | head -n1 || echo "unknown")
            log_success "$tool: $version"
        else
            log_error "$tool: not found"
            ((errors++))
        fi
    done
    
    # Check RISC-V toolchain
    if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
        local gcc_version=$(riscv32-unknown-elf-gcc --version | head -n1)
        log_success "RISC-V GCC: $gcc_version"
    else
        log_error "RISC-V toolchain: not found"
        ((errors++))
    fi
    
    # Check Python packages
    if [[ -d "venv" ]]; then
        source venv/bin/activate
        for package in numpy torch cocotb pytest; do
            if python -c "import $package" 2>/dev/null; then
                local version=$(python -c "import $package; print($package.__version__)" 2>/dev/null || echo "unknown")
                log_success "Python $package: $version"
            else
                log_error "Python $package: not found"
                ((errors++))
            fi
        done
        deactivate
    else
        log_error "Python virtual environment: not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All tools installed successfully!"
        log_info "Run 'make setup' to complete the setup"
        log_info "Run 'make help' to see available commands"
    else
        log_error "Found $errors errors. Please fix and re-run."
        return 1
    fi
}

# Performance tuning for M1
tune_performance() {
    log_info "Applying M1 performance optimizations..."
    
    # Create performance tuning script
    cat > scripts/setup/m1_performance.sh << 'EOF'
#!/bin/bash
# M1 Performance Optimizations for UnifiedRISCV

# Compiler flags for M1
export CFLAGS="-O3 -march=native -mtune=native"
export CXXFLAGS="-O3 -march=native -mtune=native"

# Thread configuration for M1 (8 performance cores + 4 efficiency cores)
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8

# Memory optimizations
export MALLOC_NANO=1

# Verilator optimizations
export VERILATOR_NUM_THREADS=8

echo "M1 performance optimizations applied"
EOF
    
    chmod +x scripts/setup/m1_performance.sh
    log_success "Performance tuning script created"
}

# Create project shortcuts
create_shortcuts() {
    log_info "Creating development shortcuts..."
    
    # Create useful aliases
    cat > scripts/setup/aliases.sh << 'EOF'
#!/bin/bash
# UnifiedRISCV Development Aliases

alias urisc='cd $UNIFIED_RISCV_ROOT'
alias build='make verilate'
alias sim='make sim'
alias test='make test-python'
alias waves='make waves'
alias bench='make benchmark'
alias clean='make clean'

# Quick simulation with common tests
alias sim-basic='make sim && echo "Basic simulation complete"'
alias sim-gpu='cd verification/tests && python test_gpu_ops.py'

# Development helpers
alias rtl='cd rtl'
alias soft='cd software'
alias verif='cd verification'
alias docs='cd docs'

echo "UnifiedRISCV aliases loaded"
EOF
    
    chmod +x scripts/setup/aliases.sh
    log_success "Development shortcuts created"
}

# Main installation function
main() {
    log_info "UnifiedRISCV Development Environment Setup for Apple Silicon"
    log_info "================================================================"
    
    # Check system
    check_apple_silicon
    
    # Install components
    install_homebrew
    install_dev_tools
    install_python_env
    install_fpga_tools
    
    # Configure environment
    configure_environment
    tune_performance
    create_shortcuts
    
    # Verify installation
    verify_installation
    
    log_success "Setup completed successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "1. Restart your terminal or run: source ~/.zshrc"
    log_info "2. Navigate to the project directory"
    log_info "3. Run: make setup"
    log_info "4. Run: make sim"
    log_info ""
    log_info "For help: make help"
    log_info "Documentation: docs/README.md"
}

# Run main function
main "$@"