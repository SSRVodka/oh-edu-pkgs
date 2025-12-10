#include <iostream>
#include <string>
#include <vector>
#include <cstdlib>
#include <sstream>
#include <fstream>
#include <filesystem>

namespace fs = std::filesystem;

static constexpr int CMD_BUFSIZE = 16384;
// modified by script at compile time
static const std::string NATIVE_LLVM_CONFIG = "";
static const std::string TARGET_LLVM_PREFIX = "";
static const std::string OHOS_LIBDIR = "";
static const std::string OHOS_CPU = "";


// Helper function to execute a command and capture output
std::string exec_command(const std::string& cmd) {
    std::string result;
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        std::cerr << "Error: Failed to execute command: " << cmd << std::endl;
        return "";
    }
    
    char buffer[CMD_BUFSIZE];
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result += buffer;
    }
    
    pclose(pipe);
    
    // Remove trailing newline
    if (!result.empty() && result.back() == '\n') {
        result.pop_back();
    }
    
    return result;
}

// Load environment variables from setup.sh
void load_setup() {
    // Source the setup.sh file and export variables
    // This is a simplified approach - in practice you'd need to parse the file
    std::string cmd = ". ./setup.sh && env";
    // For now, we'll assume the environment is already set up
}

int main(int argc, char* argv[]) {

    if (NATIVE_LLVM_CONFIG.empty() || TARGET_LLVM_PREFIX.empty()
        || OHOS_LIBDIR.empty() || OHOS_CPU.empty()) {
        std::cerr << "Error: " << argv[0] << ": paths are not configured at compile time" << std::endl;
        return 1;
    }
    
    // Process each argument
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        
        if (arg == "--cflags" || arg == "--cppflags" || arg == "--cxxflags") {
            // Get native options and append target include path
            std::string cmd = NATIVE_LLVM_CONFIG + " " + arg;
            std::string native_options = exec_command(cmd);
            std::cout << native_options << " -I" << TARGET_LLVM_PREFIX << "/include" << std::endl;
            
        } else if (arg == "--ldflags") {
            std::cout << "-L" << TARGET_LLVM_PREFIX << "/" << OHOS_LIBDIR << std::endl;
            
        } else if (arg == "--bindir") {
            std::cout << TARGET_LLVM_PREFIX << "/bin" << std::endl;
            
        } else if (arg == "--cmakedir") {
            std::cout << TARGET_LLVM_PREFIX << "/" << OHOS_LIBDIR << "/cmake/llvm" << std::endl;
            
        } else if (arg == "--includedir") {
            std::cout << TARGET_LLVM_PREFIX << "/include" << std::endl;
            
        } else if (arg == "--libdir") {
            std::cout << TARGET_LLVM_PREFIX << "/" << OHOS_LIBDIR << std::endl;
            
        } else if (arg == "--host-target") {
            std::cout << OHOS_CPU << "-unknown-linux-ohos" << std::endl;
            
        } else if (arg == "--libfiles") {
            // Get libfiles from native config
            std::string cmd = NATIVE_LLVM_CONFIG + " --libfiles";
            std::string libfiles_str = exec_command(cmd);
            
            std::istringstream iss(libfiles_str);
            std::string lib;
            std::vector<std::string> result;
            
            while (iss >> lib) {
                fs::path lib_path(lib);
                std::string basename = lib_path.filename().string();
                std::string new_path = TARGET_LLVM_PREFIX + "/" + OHOS_LIBDIR + "/" + basename;
                result.push_back(new_path);
            }
            
            // Print result
            for (size_t i = 0; i < result.size(); i++) {
                if (i > 0) std::cout << " ";
                std::cout << result[i];
            }
            std::cout << std::endl;
            
        } else if (arg == "--obj-root" || arg == "--prefix") {
            std::cout << TARGET_LLVM_PREFIX << std::endl;
            
        } else if (arg == "--libnames" || arg == "--libs") {
            // Pass through to native llvm-config
            std::string cmd = NATIVE_LLVM_CONFIG + " " + arg;
            std::string output = exec_command(cmd);
            std::cout << output << std::endl;
            
        } else if (arg == "--ignore-libllvm" || arg == "--link-shared" || arg == "--link-static") {
            std::cerr << "Error: " << argv[0] << ": unsupported option '" << arg << "'" << std::endl;
            return 1;
            
        } else {
            // Pass through to native llvm-config
            std::string cmd = NATIVE_LLVM_CONFIG + " " + arg;
            std::string output = exec_command(cmd);
            std::cout << output << std::endl;
        }
    }
    
    return 0;
}
