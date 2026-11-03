#include "include/bed_reader_bridge.h"
#include <iostream>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <filename.bed>" << std::endl;
        return 1;
    }

    try {
        // 1. Create the Bed object (calls Rust)
        auto bed = new_bed(argv[1]);

        std::cout << "Individuals: " << bed->get_iid_count() << std::endl;
        std::cout << "SNPs: " << bed->get_sid_count() << std::endl;

        auto genotypes = bed->read_all_genotypes();
        if (!genotypes.empty()) {
            std::cout << "First genotype value: " << genotypes[0] << std::endl;
        }

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}