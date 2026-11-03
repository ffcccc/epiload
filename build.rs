   fn main() {
       cxx_build::bridge("src/lib.rs")
           .compile("bed_reader_bridge");
   }