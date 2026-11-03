#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        // We leave this empty unless we want to call C++ from Rust
    }

    extern "Rust" {
        type BedWrapper;

        // Constructor: returns a rust::Box in C++
        fn new_bed(path: &str) -> Result<Box<BedWrapper>>;

        // Get total number of individuals
        fn get_iid_count(self: &mut BedWrapper) -> Result<usize>;

        // Get total number of SNPs
        fn get_sid_count(self: &mut BedWrapper) -> Result<usize>;

        // Read all genotypes as a flat vector of floats
        fn read_all_genotypes(self: &BedWrapper) -> Result<Vec<f32>>;
    }
}

// This is the actual Rust struct that holds the bed-reader object
pub struct BedWrapper {
    inner: bed_reader::Bed,
}

pub fn new_bed(path: &str) -> Result<Box<BedWrapper>, Box<bed_reader::BedErrorPlus>> {
    BedWrapper::new(path)
}

impl BedWrapper {
    // Implementation of the constructor
    pub fn new(path: &str) -> Result<Box<Self>, Box<bed_reader::BedErrorPlus>> {
        let bed = bed_reader::Bed::new(path)?;
        Ok(Box::new(BedWrapper { inner: bed }))
    }

    pub fn get_iid_count(&mut self) -> Result<usize, Box<bed_reader::BedErrorPlus>> {
        self.inner.iid_count()
    }

    pub fn get_sid_count(&mut self) -> Result<usize, Box<bed_reader::BedErrorPlus>> {
        self.inner.sid_count()
    }

    pub fn read_all_genotypes(&self) -> Result<Vec<f32>, Box<bed_reader::BedErrorPlus>> {
        let mut bed_clone = self.inner.clone();
        let val = bed_reader::ReadOptions::builder().f32().read(&mut bed_clone)?;
        let (values, _) = val.into_raw_vec_and_offset();
        Ok(values)
    }
}